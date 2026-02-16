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
    principal_ids = Array(params[:principal_ids])

    company_info = load_company_info
    all_principals = load_principals
    principals = principal_ids.filter_map { |id| all_principals.find { |p| p['id'] == id } }

    if principals.empty?
      redirect_to template_path(template), alert: 'No valid principals selected'
      return
    end

    submitter_roles = template.submitters.map { |s| s['name'] }
    fields_by_name = template.fields.index_by { |f| f['name'] }

    submissions_attrs = if principals.size == 1 || submitter_roles.size == 1
                          build_single_signer_attrs(template, principals.first, company_info,
                                                    field_values, data_paths, fields_by_name, submitter_roles.first)
                        else
                          build_multi_signer_attrs(template, principals, company_info,
                                                   fields_by_name, submitter_roles)
                        end

    submissions = Submissions.create_from_submitters(
      template: template,
      user: current_user,
      source: :invite,
      submitters_order: submitter_roles.size > 1 ? 'preserved' : 'random',
      submissions_attrs: submissions_attrs,
      params: { 'send_email' => params[:send_email] != '0', 'send_completed_email' => true }
    )

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)

    # Set only_required_fields preference on each submitter
    submissions.each do |submission|
      submission.submitters.each do |submitter|
        submitter.update_column(:preferences, submitter.preferences.merge('only_required_fields' => true))
      end
    end

    # Save field mappings for this template so subsequent sends use verified mappings
    save_company_field_mappings(template, data_paths) if data_paths.present?

    principal_names = principals.map { |p| "#{p['first_name']} #{p['last_name']}".strip }.join(' & ')
    redirect_to template_path(template), notice: "Sent to #{principal_names} for signature"
  rescue Submissions::CreateFromSubmitters::BaseError => e
    redirect_to template_path(params[:template_id]), alert: "Error creating submission: #{e.message}"
  end

  private

  def build_single_signer_attrs(template, principal, company_info, field_values, data_paths, fields_by_name, role)
    # Build fields array with pre-filled values
    fields = field_values.map do |field_name, value|
      entry = { 'name' => field_name, 'default_value' => value }
      entry['required'] = true if data_paths.key?(field_name)
      entry
    end

    # Ensure signature/initials/date fields are required
    template.fields.each do |f|
      next unless %w[signature initials date].include?(f['type'])
      next if fields.any? { |e| e['name'] == f['name'] }

      fields << { 'name' => f['name'], 'required' => true }
    end

    # Build UUID-keyed submitter_values
    submitter_values = {}
    field_values.each do |field_name, value|
      field = fields_by_name[field_name]
      submitter_values[field['uuid']] = value if field && value.present?
    end

    [{
      submitters: [{
        email: principal['email'],
        name: "#{principal['first_name']} #{principal['last_name']}".strip,
        role: role,
        fields: fields,
        values: submitter_values
      }.with_indifferent_access]
    }]
  end

  def build_multi_signer_attrs(template, principals, company_info, fields_by_name, submitter_roles)
    template_fields = template.fields.map { |f| { 'name' => f['name'], 'type' => f['type'] } }
    saved_mappings = load_company_field_mappings(template.id)

    submitters = []
    principals.each_with_index do |principal, idx|
      role = submitter_roles[idx] || submitter_roles.last

      # Run field mapping for each principal, using saved mappings if available
      result = MerchantFieldMapper.get_field_map_for_template(
        template.id, company_info, principal, template_fields, saved_mappings
      )

      # Build fields array
      fields = result[:values].map do |field_name, value|
        entry = { 'name' => field_name, 'default_value' => value }
        entry['required'] = true if result[:data_paths].key?(field_name)
        entry
      end

      # Ensure signature/initials/date are required
      template.fields.each do |f|
        next unless %w[signature initials date].include?(f['type'])
        next if fields.any? { |e| e['name'] == f['name'] }

        fields << { 'name' => f['name'], 'required' => true }
      end

      # Build UUID-keyed values
      submitter_values = {}
      result[:values].each do |field_name, value|
        field = fields_by_name[field_name]
        submitter_values[field['uuid']] = value if field && value.present?
      end

      submitters << {
        email: principal['email'],
        name: "#{principal['first_name']} #{principal['last_name']}".strip,
        role: role,
        fields: fields,
        values: submitter_values
      }.with_indifferent_access
    end

    [{ submitters: submitters }]
  end

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
