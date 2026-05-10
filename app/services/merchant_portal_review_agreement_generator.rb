# frozen_string_literal: true

require 'set'

# Creates merchant-specific review agreement templates/submissions when the
# portal-created onboarding agreements are prepared. This mirrors the current
# Split website/Split Signature orchestration:
#   master v2.0 template -> merchant-named pending clone -> field defaults on
#   the clone -> no-email portal submission -> merchant_documents writeback.
module MerchantPortalReviewAgreementGenerator
  DEFAULT_MASTER_TEMPLATE_IDS = [84, 85, 87, 78, 91, 94, 95, 96, 103].freeze
  GENERATED_SOURCE = 'merchant_portal_review_agreements'
  PORTAL_ONBOARDING_SOURCE = 'merchant_portal_onboarding'
  DEFAULT_PENDING_FOLDER = 'pending'
  DEFAULT_SORT_OFFSET = 100
  INTERACTIVE_FIELD_TYPES = Set.new(%w[signature initials stamp image file]).freeze
  ALWAYS_BLANK_NORMALIZED = Set.new(%w[
    merchantnumber agreementcontractnumber relationshipcodercnumber acknowledgementdate numberofassets
  ]).freeze

  module_function

  def maybe_generate_for_portal_onboarding(submissions)
    Array.wrap(submissions).each do |submission|
      submitter = MerchantPortalDocumentSync.merchant_submitter_for(submission)
      next unless portal_onboarding_submitter?(submitter)

      merchant_id = submitter.metadata&.dig('merchant_id').presence
      next if merchant_id.blank?

      call(merchant_id:, source_submitter: submitter)
    rescue StandardError => e
      Rails.logger.warn("[MerchantPortalReviewAgreementGenerator] failed for submission #{submission&.id}: #{e.class}: #{e.message}")
    end
  end

  def portal_onboarding_submitter?(submitter)
    submitter&.metadata&.dig('source').to_s == PORTAL_ONBOARDING_SOURCE
  end

  def call(merchant_id:, source_submitter: nil)
    return { attempted: false, skipped: true, created_count: 0, existing_count: 0, errors: ['merchant_id is required'] } if merchant_id.blank?

    merchant = SupabaseClient.fetch_merchant(merchant_id)
    principal = SupabaseClient.fetch_principals(merchant_id)&.first || {}
    decrypt_records!(merchant, principal)

    author = source_submitter&.submission&.created_by_user || default_author
    raise 'No DocuSeal user available for generated review agreements' unless author

    existing_documents = SupabaseClient.fetch_merchant_documents(merchant_id)
    active_template_ids = existing_documents.map { |doc| doc['template_id'].to_i }.to_set
    result = { attempted: true, skipped: false, created_count: 0, existing_count: 0, template_ids: [], errors: [] }

    configured_master_template_ids.each_with_index do |master_template_id, index|
      master = Template.active.find_by(id: master_template_id)
      unless master
        result[:errors] << "Master review template #{master_template_id} not found"
        next
      end

      clone = find_or_create_clone(master, merchant, principal, author)
      result[:template_ids] << clone.id

      if active_template_ids.include?(clone.id)
        result[:existing_count] += 1
        next
      end

      submission = find_existing_submission(clone, merchant_id) || create_portal_submission(clone, merchant, principal, author)
      submitter = MerchantPortalDocumentSync.merchant_submitter_for(submission)
      MerchantPortalDocumentSync.sync_submission(
        submission,
        clone,
        {
          merchant_id:,
          template_name: clone.name,
          sort_order: sort_offset + index,
          artifact: {
            master_template: master.name,
            master_template_id: master.id,
            template_id: clone.id,
            submission_id: submission.id,
            review_url: review_url_for(clone)
          }
        },
        submitter
      )
      result[:created_count] += 1
    rescue StandardError => e
      result[:errors] << "#{master_template_id}: #{e.class}: #{e.message}"
    end

    result[:skipped] = result[:created_count].zero? && result[:errors].empty?
    result
  end

  def configured_master_template_ids
    raw = ENV['SPLIT_REVIEW_AGREEMENT_TEMPLATE_IDS'].presence || DEFAULT_MASTER_TEMPLATE_IDS.join(',')
    ids = raw.split(',').filter_map do |item|
      value = item.to_s.strip.to_i
      value.positive? ? value : nil
    end
    ids.presence || DEFAULT_MASTER_TEMPLATE_IDS
  end

  def sort_offset
    ENV.fetch('SPLIT_REVIEW_AGREEMENT_SORT_OFFSET', DEFAULT_SORT_OFFSET).to_i
  end

  def pending_folder_name
    ENV.fetch('SPLIT_REVIEW_AGREEMENT_FOLDER', DEFAULT_PENDING_FOLDER)
  end

  def default_author
    User.find_by(email: ENV['SPLIT_REVIEW_AGREEMENT_AUTHOR_EMAIL'].presence || 'admin@split-llc.com') || User.order(:id).first
  end

  def decrypt_records!(merchant, principal)
    MerchantPii.decrypt_merchant(merchant) if defined?(MerchantPii) && merchant.present?
    MerchantPii.decrypt_principal(principal) if defined?(MerchantPii) && principal.present?
  rescue StandardError => e
    Rails.logger.warn("[MerchantPortalReviewAgreementGenerator] PII decrypt skipped: #{e.class}: #{e.message}")
  end

  def find_or_create_clone(master, merchant, principal, author)
    external_id = clone_external_id(master.id, merchant['id'])
    clone = Template.active.find_by(external_id:)
    return clone if clone

    clone = Templates::Clone.call(
      master,
      author:,
      external_id:,
      name: clone_name(master, merchant),
      folder_name: pending_folder_name
    )
    clone.preferences = clone.preferences.merge(
      'merchant_portal_review_agreement' => true,
      'source' => GENERATED_SOURCE,
      'merchant_id' => merchant['id'],
      'master_template_id' => master.id,
      'master_template_name' => master.name
    )
    apply_prefill_defaults!(clone, master, merchant, principal)
    Templates::CloneAttachments.call(template: clone, original_template: master)
    clone
  end

  def clone_external_id(master_template_id, merchant_id)
    "#{GENERATED_SOURCE}:#{merchant_id}:#{master_template_id}"
  end

  def clone_name(master, merchant)
    slug = merchant_slug(merchant)
    slug.present? ? "#{master.name}_#{slug}" : master.name
  end

  def merchant_slug(merchant)
    raw = merchant['business_name'].presence || merchant['dba_name'].presence || merchant['id'].to_s
    raw.to_s.gsub(/[^a-zA-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '').downcase
  end

  def find_existing_submission(template, merchant_id)
    template.submissions.active.includes(:submitters).detect do |submission|
      submission.submitters.any? { |submitter| submitter.metadata&.dig('merchant_id').to_s == merchant_id.to_s }
    end
  end

  def create_portal_submission(template, merchant, principal, author)
    role = template.submitters.first || {}
    submitters = [{
      role: role['name'],
      uuid: role['uuid'],
      name: merchant_submitter_name(merchant, principal),
      email: merchant_submitter_email(merchant),
      metadata: {
        'merchant_id' => merchant['id'],
        'source' => GENERATED_SOURCE,
        'review_agreement_template_id' => template.id,
        'review_master_template_id' => template.preferences['master_template_id'],
        'review_master_template_name' => template.preferences['master_template_name']
      }
    }.with_indifferent_access]

    submissions = Submissions.create_from_submitters(
      template:,
      user: author,
      source: :api,
      submitters_order: 'preserved',
      submissions_attrs: [{ submitters: }],
      params: { 'send_email' => false, 'send_sms' => false }
    )
    SearchEntries.enqueue_reindex(submissions) if defined?(SearchEntries)
    submissions.first
  end

  def merchant_submitter_name(merchant, principal)
    principal_name = [principal&.dig('first_name'), principal&.dig('last_name')].compact_blank.join(' ').strip
    principal_name.presence || merchant['contact_name'].presence || merchant['business_name'].presence || merchant['dba_name'].presence || 'Merchant'
  end

  def merchant_submitter_email(merchant)
    merchant['business_email'].presence || merchant['email'].presence
  end

  def apply_prefill_defaults!(clone, master, merchant, principal)
    normalized_merchant = normalize_merchant_for_mapping(merchant)
    template_fields = clone.fields.map { |field| { 'name' => field['name'], 'type' => field['type'] } }
    saved_mappings = SupabaseClient.fetch_template_field_mappings(master.id)
    mapped = MerchantFieldMapper.get_field_map_for_template(master.id, normalized_merchant, principal || {}, template_fields, saved_mappings)
    values_by_name = mapped[:values] || {}
    agent_only_fields = Set.new(mapped[:agent_only_fields] || [])

    clone.fields = clone.fields.map do |field|
      next field if interactive_field?(field)

      field_name = field['name'].to_s
      next field if agent_only_fields.include?(field['uuid']) || agent_only_fields.include?(field_name)

      value = field_name.present? ? values_by_name[field_name] : nil
      value = hardcoded_value_for(field, normalized_merchant, principal || {}) if value.blank?
      value = install_exec_position_value(field, normalized_merchant) if value.blank? && master.id.to_i == 103
      value = nil if ALWAYS_BLANK_NORMALIZED.include?(normalize_field_name(field_name))
      next field if value.blank?
      next field if field['type'] == 'checkbox' && value.to_s != 'true'

      field.merge('default_value' => value.to_s)
    end
  end

  def normalize_merchant_for_mapping(merchant)
    merchant.merge(
      'email' => merchant['email'].presence || merchant['business_email'],
      'phone' => merchant['phone'].presence || merchant['business_phone']
    )
  end

  def interactive_field?(field)
    INTERACTIVE_FIELD_TYPES.include?(field['type'].to_s)
  end

  def normalize_field_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9]/, '')
  end

  # Ported from the existing Hermes review-doc generator as a deterministic
  # fill-in-the-gaps pass after saved template mappings / portal field mapping.
  def hardcoded_value_for(field, merchant, principal)
    key = normalize_field_name(field['name'])
    lookup = hardcoded_lookup(merchant, principal)
    lookup[key]
  end

  # rubocop:disable Metrics/MethodLength
  def hardcoded_lookup(merchant, principal)
    phone = merchant['phone'].presence || merchant['business_phone'].presence || ''
    owner_phone = principal['mobile_phone'].presence || principal['phone'].presence || principal['home_phone'].presence || phone
    owner_name = principal['_full_name'].presence || [principal['first_name'], principal['last_name']].compact_blank.join(' ').strip
    address = merchant['_address_line1'].presence || merchant['street'].presence || ''
    zip_code = merchant['_zip'].presence || merchant['zip'].presence || ''
    seasonal_months = Array.wrap(merchant['seasonal_months'])
    bank_name = merchant['bank_name'].presence || ''
    bank_routing_number = merchant['bank_routing_number'].presence || ''
    bank_account_number = merchant['bank_account_number'].presence || ''
    owner_home_address = principal['_home_address'].presence || join_address(
      principal['street'], principal['street2'], principal['city'], principal['state'], principal['_zip'].presence || principal['zip']
    ) || merchant['home_address'].presence || ''
    email = merchant['business_email'].presence || merchant['email'].presence || principal['email'].presence || ''

    {
      'legalname' => merchant['business_name'], 'legalbusinessname' => merchant['business_name'],
      'businessname' => merchant['business_name'], 'dba' => merchant['dba_name'], 'dbaname' => merchant['dba_name'],
      'ein' => merchant['ein'], 'taxid' => merchant['ein'], 'eintaxid' => merchant['ein'], 'federaltaxid' => merchant['ein'],
      'entitytype' => merchant['entity_type'].presence || merchant['company_type'],
      'businessstartdate' => merchant['business_start_date'], 'busstartdate' => merchant['business_start_date'],
      'startdate' => merchant['business_start_date'], 'yearsinbusiness' => merchant['years_in_business'],
      'businessaddress' => address, 'businessaddress1' => address, 'businesscity' => merchant['city'], 'city' => merchant['city'],
      'businessstate' => merchant['state'], 'state' => merchant['state'], 'businesszip' => zip_code, 'zipcode' => zip_code,
      'zip' => zip_code, 'businessphone' => phone, 'phone' => phone, 'businessnumber' => phone,
      'businessemail' => email, 'emailaddress' => email, 'email' => email, 'website' => merchant['website'],
      'typeofbusiness' => merchant['industry'].presence || merchant['product_description'],
      'businesstype' => merchant['industry'].presence || merchant['product_description'],
      'monthlyvolume' => merchant['monthly_volume'], 'averageticket' => merchant['average_ticket'], 'highticket' => merchant['high_ticket'],
      'highestmonthlyvolume' => merchant['highest_monthly_volume'], 'peakmonthlyvolume' => merchant['highest_monthly_volume'],
      'annualrevenue' => merchant['annual_revenue'], 'annualvolume' => merchant['annual_revenue'],
      'cardpresent' => merchant['card_present_pct'], 'cardpresentpct' => merchant['card_present_pct'], 'cardpresent%' => merchant['card_present_pct'],
      'cardnotpresent' => merchant['card_not_present_pct'], 'cardnotpresent%' => merchant['card_not_present_pct'],
      'ecommerce' => merchant['ecommerce_pct'], 'ecommercepct' => merchant['ecommerce_pct'], 'ecommerce%' => merchant['ecommerce_pct'],
      'moto' => merchant['moto_pct'], 'motopct' => merchant['moto_pct'], 'moto%' => merchant['moto_pct'],
      'keyed' => merchant['keyed_pct'], 'keyedpct' => merchant['keyed_pct'], 'keyed%' => merchant['keyed_pct'],
      'seasonalyes' => merchant['seasonal_business'] ? 'true' : '', 'seasonalno' => merchant['seasonal_business'] ? '' : 'true',
      'seasonaljan' => seasonal_months.include?('Jan') ? 'true' : '', 'seasonalfeb' => seasonal_months.include?('Feb') ? 'true' : '',
      'seasonalmar' => seasonal_months.include?('Mar') ? 'true' : '', 'seasonalapr' => seasonal_months.include?('Apr') ? 'true' : '',
      'seasonalapril' => seasonal_months.include?('Apr') ? 'true' : '', 'seasonalmay' => seasonal_months.include?('May') ? 'true' : '',
      'seasonaljun' => seasonal_months.include?('Jun') ? 'true' : '', 'seasonaljul' => seasonal_months.include?('Jul') ? 'true' : '',
      'seasonalaug' => seasonal_months.include?('Aug') ? 'true' : '', 'seasonalsep' => seasonal_months.include?('Sep') ? 'true' : '',
      'seasonaloct' => seasonal_months.include?('Oct') ? 'true' : '', 'seasonalnov' => seasonal_months.include?('Nov') ? 'true' : '',
      'seasonaldec' => seasonal_months.include?('Dec') ? 'true' : '', 'seasonalmonths' => seasonal_months.join(', '),
      'industryproducts' => merchant['industry'], 'industry' => merchant['industry'], 'productdescription' => merchant['product_description'],
      'owneremail' => email, 'personalemail' => email, 'homephone' => principal['home_phone'], 'mobilephone' => principal['mobile_phone'].presence || principal['phone'],
      'ownerfullname' => owner_name, 'ownername' => owner_name, 'printname' => owner_name,
      'firstname' => principal['first_name'], 'lastname' => principal['last_name'], 'title' => principal['title'],
      'ownerphone' => owner_phone, 'cellphone' => phone.presence || owner_phone, 'cellnumber' => phone.presence || owner_phone,
      'ssn' => principal['ssn'], 'dateofbirth' => principal['dob'], 'dob' => principal['dob'],
      'driverslicense' => principal['drivers_license_number'], 'dlstate' => principal['drivers_license_state'],
      'ownership' => (principal['ownership_pct'].presence || 100).to_s, 'ownershippct' => (principal['ownership_pct'].presence || 100).to_s,
      'ownership%' => (principal['ownership_pct'].presence || 100).to_s,
      'homeaddress' => owner_home_address, 'homecity' => principal['city'], 'homestate' => principal['state'], 'homezip' => principal['_zip'].presence || principal['zip'],
      'owneraddress' => principal['_address_line1'].presence || principal['street'], 'ownercity' => principal['city'],
      'ownerstate' => principal['state'], 'ownerzip' => principal['_zip'].presence || principal['zip'],
      'ownercitystatezp' => [principal['city'], [principal['state'], principal['_zip'].presence || principal['zip']].compact_blank.join(' ')].compact_blank.join(', '),
      'routing' => bank_routing_number, 'routingnumber' => bank_routing_number, 'bankroutingnumber' => bank_routing_number,
      'account' => bank_account_number, 'accountnumber' => bank_account_number, 'bankaccountnumber' => bank_account_number,
      'bankname' => bank_name, 'merchant' => merchant['business_name'], 'guarantorname' => owner_name,
      'merchantname' => merchant['business_name'], 'merchantbusinessphone' => phone, 'merchantcontactphone' => owner_phone,
      'acknowledgementdate' => '', 'merchantnumber' => '', 'agreementcontractnumber' => '', 'relationshipcodercnumber' => ''
    }.transform_values { |value| value.nil? ? '' : value.to_s }
  end
  # rubocop:enable Metrics/MethodLength

  def join_address(street = nil, street2 = nil, city = nil, state = nil, zip_code = nil)
    street_line = [street, street2].compact_blank.join(', ')
    state_zip = [state, zip_code].compact_blank.join(' ')
    locality_line = city.present? && state_zip.present? ? "#{city}, #{state_zip}" : city.presence || state_zip
    [street_line, locality_line].compact_blank.join(', ').presence
  end

  def install_exec_position_value(field, merchant)
    areas = field['areas'] || []
    return if areas.blank?

    area = areas.first
    y = area['y'].to_f
    x = area['x'].to_f
    email = merchant['business_email'].presence || merchant['email'].presence || ''
    position_map = [
      [0.303, 0.152, email],
      [0.323, 0.307, merchant['_address_line1'].presence || merchant['street'].presence || ''],
      [0.323, 0.539, merchant['city'].presence || ''],
      [0.323, 0.727, merchant['state'].presence || ''],
      [0.323, 0.825, merchant['_zip'].presence || merchant['zip'].presence || '']
    ]
    position_map.each do |py, px, value|
      return value if (y - py).abs < 0.025 && (x - px).abs < 0.025 && value.present?
    end
    nil
  end

  def review_url_for(template)
    "#{Docuseal::CONSOLE_URL}/templates/#{template.id}/edit"
  end
end
