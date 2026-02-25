# frozen_string_literal: true

class CompanySubmissionsController < ApplicationController
  before_action :authenticate_user!

  before_action do
    authorize!(:create, Submission)
  end

  def list_principals
    principals = load_principals

    render json: {
      principals: principals.map { |p|
        { id: p['id'], first_name: p['first_name'], last_name: p['last_name'], email: p['email'] }
      }
    }
  end

  def create
    template = current_account.templates.find(params[:template_id])
    field_values = params[:field_values]&.to_unsafe_h || {}
    data_paths = params[:data_paths]&.to_unsafe_h || {}

    submitter_params = (params[:submitters]&.to_unsafe_h || {}).sort_by { |k, _| k.to_i }.map(&:last)

    if submitter_params.empty? || submitter_params.all? { |sp| sp['email'].blank? }
      redirect_to template_path(template), alert: 'No valid recipients provided'
      return
    end

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

      # Build fields array with pre-filled values
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

      # Build UUID-keyed submitter_values
      submitter_values = {}
      role_values.each do |field_name, value|
        field = fields_by_name[field_name]
        submitter_values[field['uuid']] = value if field && value.present?
      end

      {
        email: sp['email'],
        name: sp['name'],
        role: role&.dig('name'),
        fields: entries,
        values: submitter_values
      }.with_indifferent_access
    end

    submitters_order = params[:preserve_order] == '1' ? 'preserved' : 'random'

    submissions = Submissions.create_from_submitters(
      template: template,
      user: current_user,
      source: :invite,
      submitters_order: submitters_order,
      submissions_attrs: [{ submitters: submitters_list }],
      params: { 'send_email' => params[:send_email] != '0', 'send_completed_email' => true }
    )

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)

    # Save field mappings for this template so subsequent sends use verified mappings
    save_company_field_mappings(template, data_paths) if data_paths.present?

    recipient_names = submitter_params.map { |sp| sp['name'] }.compact_blank.join(' & ')
    redirect_to template_path(template), notice: "Sent to #{recipient_names} for signature"
  rescue Submissions::CreateFromSubmitters::BaseError => e
    redirect_to template_path(params[:template_id]), alert: "Error creating submission: #{e.message}"
  end

  private

  def load_company_info
    current_account.encrypted_configs
                   .find_by(key: EncryptedConfig::COMPANY_INFO_KEY)&.value || {}
  end

  def load_principals
    current_account.encrypted_configs
                   .find_by(key: EncryptedConfig::COMPANY_PRINCIPALS_KEY)&.value || []
  end

  def load_company_field_mappings(template_id)
    key = "company_field_mappings_#{template_id}"
    current_account.encrypted_configs.find_by(key: key)&.value
  end

  def save_company_field_mappings(template, data_paths)
    key = "company_field_mappings_#{template.id}"
    mappings_json = data_paths.map do |field_name, data_path|
      { 'fieldName' => field_name, 'dataPath' => data_path }
    end

    config = current_account.encrypted_configs.find_or_initialize_by(key: key)
    config.value = { 'mappings' => mappings_json, 'agent_only_fields' => [] }
    config.save!
  rescue StandardError => e
    Rails.logger.warn("[CompanySubmissions] Failed to save field mappings: #{e.message}")
  end
end
