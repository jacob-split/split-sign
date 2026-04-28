# frozen_string_literal: true

class MerchantSubmissionsController < ApplicationController
  before_action :authenticate_user!

  before_action do
    authorize!(:create, Submission)
  end

  def new
    @templates = current_account.templates.active.preload(:folder).order(:name)
    @template = current_account.templates.find_by(id: params[:template_id])
  end

  def search_merchants
    merchants = SupabaseClient.fetch_merchants(params[:query])

    render json: merchants.map { |m|
      {
        id: m['id'],
        label: "#{m['dba_name'].presence || m['business_name']} — #{m['email']}",
        business_name: m['business_name'],
        dba_name: m['dba_name'],
        email: m['email']
      }
    }
  rescue SupabaseClient::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def preview
    merchant = SupabaseClient.fetch_merchant(params[:merchant_id])
    principals = SupabaseClient.fetch_principals(params[:merchant_id])
    principal = principals&.first || {}

    MerchantPii.decrypt_merchant(merchant)
    MerchantPii.decrypt_principal(principal) if principal.present?

    template = current_account.templates.find(params[:template_id])

    ActiveRecord::Associations::Preloader.new(
      records: [template],
      associations: [schema_documents: [:blob, { preview_images_attachments: :blob }]]
    ).call

    template_fields = template.fields.map { |f| { 'name' => f['name'], 'type' => f['type'] } }
    saved_mappings = SupabaseClient.fetch_template_field_mappings(template.id)

    result = MerchantFieldMapper.get_field_map_for_template(
      template.id, merchant, principal, template_fields, saved_mappings
    )

    document_pages = template.schema_documents.flat_map do |doc|
      doc.preview_images.map { |img| { url: img.url, filename: img.filename.to_s } }
    end

    render json: {
      values: result[:values],
      agent_only_fields: result[:agent_only_fields],
      data_paths: result[:data_paths],
      mapping_source: result[:source],
      template_fields: template.fields.reject { |f| MerchantFieldMapper::INTERACTIVE_TYPES.include?(f['type']) }
                                       .map { |f| { 'uuid' => f['uuid'], 'name' => f['name'], 'type' => f['type'] } },
      document_pages: document_pages,
      merchant_name: merchant['business_name'],
      merchant_email: merchant['email'],
      principal_name: principal.present? ? "#{principal['first_name']} #{principal['last_name']}".strip : nil
    }
  rescue SupabaseClient::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def create
    template = current_account.templates.find(params[:template_id])
    field_values = params[:field_values]&.to_unsafe_h || {}
    agent_only_fields = params[:agent_only_fields] || []
    data_paths = params[:data_paths]&.to_unsafe_h || {}
    merchant_id = params[:merchant_id]
    merchant = merchant_id.present? ? SupabaseClient.fetch_merchant(merchant_id) : {}

    submitter_params = (params[:submitters]&.to_unsafe_h || {}).sort_by { |k, _| k.to_i }.map(&:last)

    # Group template fields by submitter_uuid for splitting values per role
    fields_by_name = template.fields.index_by { |f| f['name'] }
    fields_by_submitter = template.fields.group_by { |f| f['submitter_uuid'] }

    submitters_list = submitter_params.map.with_index do |sp, idx|
      role_uuid = sp['uuid']
      role = template.submitters.find { |s| s['uuid'] == role_uuid }
      role_fields = fields_by_submitter[role_uuid] || []
      role_field_names = role_fields.map { |f| f['name'] }.to_set

      # Filter field_values to only fields belonging to this role
      role_values = field_values.select { |name, _| role_field_names.include?(name) }

      # Build fields array with pre-filled values (only for the merchant's role — index 0)
      fields = if idx == 0
                 entries = role_values.map do |field_name, value|
                   entry = { 'name' => field_name, 'default_value' => value }
                   entry['required'] = true if data_paths.key?(field_name)
                   entry
                 end

                 # Ensure signature/initials/date fields are required
                 role_fields.each do |f|
                   next unless %w[signature initials date].include?(f['type'])
                   next if entries.any? { |e| e['name'] == f['name'] }

                   entries << { 'name' => f['name'], 'required' => true }
                 end

                 entries
               else
                 # Non-merchant roles: just ensure signature/initials/date are required
                 role_fields.select { |f| %w[signature initials date].include?(f['type']) }
                            .map { |f| { 'name' => f['name'], 'required' => true } }
               end

      # Build UUID-keyed submitter_values (only for merchant's role)
      submitter_values = {}
      if idx == 0
        role_values.each do |field_name, value|
          field = fields_by_name[field_name]
          submitter_values[field['uuid']] = value if field && value.present?
        end
      end

      attrs = {
        email: sp['email'],
        name: sp['name'],
        role: role&.dig('name'),
        fields: fields,
        values: submitter_values
      }
      if idx == 0
        metadata = { 'merchant_id' => merchant_id }
        metadata['provider_mid'] = merchant['provider_mid'] if merchant['provider_mid'].present?
        attrs[:metadata] = metadata
      end

      attrs.with_indifferent_access
    end

    submitters_order = params[:preserve_order] == '1' ? 'preserved' : 'random'

    Rails.logger.info("[MerchantSubmissions] Creating for merchant_id=#{merchant_id}, " \
                      "submitters=#{submitters_list.size}, order=#{submitters_order}")

    submissions = Submissions.create_from_submitters(
      template: template,
      user: current_user,
      source: :invite,
      submitters_order: submitters_order,
      submissions_attrs: [{ submitters: submitters_list }],
      params: { 'send_email' => params[:send_email] != '0', 'send_completed_email' => true }
    )

    MerchantPortalDocumentSync.sync_submissions(submissions, template:, merchant_id:, template_name: template.name)

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)

    submitter = submissions.first&.submitters&.first

    if submitter
      SupabaseClient.update_merchant(merchant_id, { onboarding_status: 'awaiting_signature' }) if merchant_id.present?

      # Save field mappings for this template (so next send auto-fills the same way)
      save_field_mappings(template, data_paths, agent_only_fields) if data_paths.present?

      # Set only_required_fields preference on the merchant submitter (index 0)
      submitter.update!(preferences: submitter.preferences.merge('only_required_fields' => true))
    end

    merchant_name = submitter_params.first&.dig('name') || params[:merchant_name]
    redirect_to template_path(template), notice: "Sent to #{merchant_name} for signature"
  rescue Submissions::CreateFromSubmitters::BaseError => e
    redirect_to new_merchant_submission_path(template_id: params[:template_id]),
                alert: "Error creating submission: #{e.message}"
  rescue SupabaseClient::Error => e
    redirect_to template_path(params[:template_id]),
                notice: "Submission created but Supabase update failed: #{e.message}"
  end

  private

  def save_field_mappings(template, data_paths, agent_only_fields)
    SupabaseClient.upsert_template_field_mappings(template.id, data_paths, agent_only_fields, template_name: template.name)
  rescue SupabaseClient::Error => e
    Rails.logger.warn("[MerchantSubmissions] Failed to save field mappings: #{e.message}")
  end
end
