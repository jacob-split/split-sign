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
    merchant_email = params[:merchant_email]
    merchant_name = params[:merchant_name]
    merchant_id = params[:merchant_id]

    # Build fields array with name-based default values
    fields = field_values.map do |field_name, value|
      entry = { 'name' => field_name, 'default_value' => value }
      entry['readonly'] = true if agent_only_fields.include?(field_name)
      entry
    end

    submitter_role = template.submitters.first['name']

    submissions_attrs = [{
      submitters: [{
        email: merchant_email,
        name: merchant_name,
        role: submitter_role,
        fields: fields,
        readonly_fields: agent_only_fields,
        metadata: { 'merchant_id' => merchant_id }
      }]
    }]

    submissions = Submissions.create_from_submitters(
      template: template,
      user: current_user,
      source: :api,
      submitters_order: 'random',
      submissions_attrs: submissions_attrs,
      params: { 'send_email' => params[:send_email] != '0' }
    )

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)

    submitter = submissions.first&.submitters&.first

    if submitter
      # Write to Supabase merchant_documents
      SupabaseClient.insert_merchant_document({
        merchant_id: merchant_id,
        template_id: template.id,
        template_name: template.name,
        submission_id: submitter.submission_id,
        submitter_slug: submitter.slug,
        embed_src: "#{Docuseal::CONSOLE_URL}/s/#{submitter.slug}",
        status: 'sent'
      })

      SupabaseClient.update_merchant(merchant_id, { onboarding_status: 'awaiting_signature' })

      # Save field mappings for this template (so next send auto-fills the same way)
      save_field_mappings(template, data_paths, agent_only_fields) if data_paths.present?
    end

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
