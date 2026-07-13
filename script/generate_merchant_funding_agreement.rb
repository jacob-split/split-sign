# frozen_string_literal: true

# Generate one portal-only FRPA + Payroc Letter of Direction submission from
# the restored master templates. Run with:
#   bundle exec rails runner script/generate_merchant_funding_agreement.rb CONFIG.json
#
# CONFIG.json contains merchant_id and the approved deal economics. Merchant,
# principal, and bank data are always fetched from the live funding portal.

require 'json'
require 'digest'

config_path = ARGV.fetch(0) { raise ArgumentError, 'CONFIG.json path is required' }
config = JSON.parse(File.read(config_path))

merchant_id = config.fetch('merchant_id')
purchase_price = BigDecimal(config.fetch('purchase_price').to_s)
factor_rate = BigDecimal(config.fetch('factor_rate').to_s)
origination_fee = BigDecimal(config.fetch('origination_fee', 0).to_s)
specified_percentage = BigDecimal(config.fetch('specified_percentage').to_s)
agreement_date = Date.iso8601(config.fetch('agreement_date', Date.current.iso8601))
title_override = config['title'].presence
sort_order = config.fetch('sort_order', 200).to_i

raise ArgumentError, 'purchase_price must be positive' unless purchase_price.positive?
raise ArgumentError, 'factor_rate must be at least 1.0' unless factor_rate >= 1
raise ArgumentError, 'origination_fee cannot be negative' if origination_fee.negative?
unless specified_percentage.positive? && specified_percentage <= 100
  raise ArgumentError, 'specified_percentage must be between 0 and 100'
end

frpa_master = Template.active.find_by(id: 95)
lod_master = Template.active.find_by(id: 94)
raise 'Restored FRPA master 95 is missing' unless frpa_master
raise 'Restored LOD master 94 is missing' unless lod_master
raise 'FRPA master 95 has no fields' if frpa_master.fields.blank?
raise 'LOD master 94 has no fields' if lod_master.fields.blank?

merchant = SupabaseClient.fetch_merchant(merchant_id)
principal = SupabaseClient.fetch_principals(merchant_id)&.first || {}
MerchantPortalReviewAgreementGenerator.decrypt_records!(merchant, principal)
raise "Merchant not found: #{merchant_id}" if merchant.blank?

author = User.find_by(email: ENV['SPLIT_REVIEW_AGREEMENT_AUTHOR_EMAIL'].presence || 'jacob@split-llc.com') || User.order(:id).first
raise 'No Split Signature author is available' unless author

owner_name = [principal['first_name'], principal['last_name']].compact_blank.join(' ').strip
owner_name = merchant['contact_name'].presence || merchant['business_name'] if owner_name.blank?
merchant_email = merchant['business_email'].presence || merchant['email'].presence || principal['email'].presence
raise 'Merchant signer email is missing' if merchant_email.blank?

deal_key = [
  merchant_id,
  agreement_date.iso8601,
  format('%.2f', purchase_price),
  format('%.4f', factor_rate),
  format('%.4f', specified_percentage)
].join(':')
external_id = "funding_portal_frpa_lod:#{Digest::SHA256.hexdigest(deal_key)[0, 24]}"
template_name = "#{merchant['business_name']} - FRPA + Payroc Letter of Direction - #{agreement_date.strftime('%m-%d-%Y')}"

combined = Template.active.find_by(external_id: external_id)
created_template = false

unless combined
  combined = Templates::Clone.call(
    frpa_master,
    author: author,
    external_id: external_id,
    name: template_name,
    folder_name: 'pending'
  )
  combined.source = :api
  combined.shared_link = false
  combined.preferences = combined.preferences.merge(
    'source' => 'funding_portal_frpa_lod',
    'merchant_id' => merchant_id,
    'frpa_master_template_id' => frpa_master.id,
    'lod_master_template_id' => lod_master.id,
    'deal_key' => deal_key,
    'funding_field_layout_version' => 8
  )
  Templates::CloneAttachments.call(template: combined, original_template: frpa_master)

  lod_submitters, lod_fields, = Templates::Clone.update_submitters_and_fields_and_schema(
    lod_master.submitters.deep_dup,
    lod_master.fields.deep_dup,
    lod_master.schema.deep_dup,
    lod_master.preferences.deep_dup
  )
  role_mapping = {}
  lod_submitters.each do |submitter|
    existing_role = combined.submitters.find { |item| item['name'] == submitter['name'] }
    if existing_role
      role_mapping[submitter['uuid']] = existing_role['uuid']
    else
      combined.submitters << submitter
      role_mapping[submitter['uuid']] = submitter['uuid']
    end
  end

  lod_document = lod_master.schema_documents.first
  raise 'LOD master has no source document' unless lod_document

  lod_attachment_uuid = SecureRandom.uuid
  new_lod_document = combined.documents_attachments.new(
    uuid: lod_attachment_uuid,
    blob_id: lod_document.blob_id
  )
  Templates::CloneAttachments.clone_document_preview_images_attachments(
    document: lod_document,
    new_document: new_lod_document
  )
  lod_fields.each do |field|
    field['submitter_uuid'] = role_mapping[field['submitter_uuid']] || field['submitter_uuid']
    Array.wrap(field['areas']).each { |area| area['attachment_uuid'] = lod_attachment_uuid }
    combined.fields << field
  end
  combined.schema << { 'attachment_uuid' => lod_attachment_uuid, 'name' => lod_master.name }
  combined.save!
  created_template = true
end

business_address_full = MerchantPortalReviewAgreementGenerator.join_address(
  merchant['street'], merchant['street2'], merchant['city'], merchant['state'], merchant['_zip'].presence || merchant['zip']
)
home_address_full = MerchantPortalReviewAgreementGenerator.join_address(
  principal['street'], principal['street2'], principal['city'], principal['state'], principal['_zip'].presence || principal['zip']
)
title = title_override || principal['title'].presence || 'Owner'
company_type = merchant['entity_type'].presence || merchant['company_type'].presence || 'LLC'
purchased_amount = (purchase_price * factor_rate).round(2)
net_amount = (purchase_price - origination_fee).round(2)

exact_values = {
  'legalname' => merchant['business_name'],
  'legalbusinessname' => merchant['business_name'],
  'dbaname' => merchant['dba_name'],
  'entityandstate' => [company_type.to_s.upcase, merchant['state']].compact_blank.join(' - '),
  'businessaddress' => merchant['street'],
  'businessaddressfull' => business_address_full,
  'city' => merchant['city'],
  'state' => merchant['state'],
  'businesszip' => merchant['_zip'].presence || merchant['zip'],
  'ownerfullname' => owner_name,
  'merchantsignername' => owner_name,
  'title' => title,
  'businessphone' => merchant['phone'].presence || merchant['business_phone'],
  'ownerphone' => principal['mobile_phone'].presence || principal['phone'].presence || merchant['phone'].presence || merchant['business_phone'],
  'bankname' => merchant['bank_name'],
  'routingnumber' => merchant['bank_routing_number'],
  'accountnumber' => merchant['bank_account_number'],
  'accountname' => merchant['business_name'],
  'eintaxid' => merchant['ein'],
  'businessemail' => merchant_email,
  'owneremail' => principal['email'].presence || merchant_email,
  'homeaddress' => home_address_full.presence || principal['street'],
  'agreementdate' => agreement_date.strftime('%m/%d/%Y'),
  'purchaseprice' => format('%.2f', purchase_price),
  'initialperiodicamount' => 'Variable',
  'purchasedamount' => format('%.2f', purchased_amount),
  'specifiedpercentage' => format('%g', specified_percentage),
  'priorbalance' => '0.00',
  'achprogramfee' => '0.00',
  'originationfee' => format('%.2f', origination_fee),
  'netamountfunded' => format('%.2f', net_amount),
  'factorrate' => "Factor Rate: #{format('%g', factor_rate)}",
  'fundingagreementtype' => 'FRPA',
  'fundingcompany' => 'Split LLC'
}.transform_values { |value| value.nil? ? '' : value.to_s }

fallback_values = MerchantPortalReviewAgreementGenerator.hardcoded_lookup(merchant, principal)
interactive_types = MerchantPortalReviewAgreementGenerator::INTERACTIVE_FIELD_TYPES

combined.fields = combined.fields.map do |field|
  next field if interactive_types.include?(field['type'].to_s)

  key = MerchantPortalReviewAgreementGenerator.normalize_field_name(field['name'])
  value = exact_values[key].presence || fallback_values[key].presence || field['default_value'].presence
  next field if value.blank?

  field.merge('default_value' => value.to_s, 'readonly' => true, 'required' => false)
end
combined.save!

signature_count = combined.fields.count { |field| field['type'].to_s == 'signature' }
raise "Combined template expected 7 signatures, found #{signature_count}" unless signature_count == 7
raise "Combined template expected 2 documents, found #{combined.schema.size}" unless combined.schema.size == 2

submission = combined.submissions.active.includes(:submitters).detect do |candidate|
  candidate.submitters.any? do |submitter|
    submitter.metadata&.dig('merchant_id').to_s == merchant_id.to_s &&
      submitter.metadata&.dig('source').to_s == 'funding_portal_frpa_lod'
  end
end
created_submission = false

unless submission
  role = combined.submitters.first || raise('Combined template has no merchant role')
  submitters = [{
    role: role['name'],
    uuid: role['uuid'],
    name: owner_name,
    email: merchant_email,
    metadata: {
      'merchant_id' => merchant_id,
      'source' => 'funding_portal_frpa_lod',
      'purchase_price' => purchase_price.to_s('F'),
      'purchased_amount' => purchased_amount.to_s('F'),
      'factor_rate' => factor_rate.to_s('F'),
      'specified_percentage' => specified_percentage.to_s('F'),
      'origination_fee' => origination_fee.to_s('F')
    }
  }.with_indifferent_access]
  submission = Submissions.create_from_submitters(
    template: combined,
    user: author,
    source: :api,
    submitters_order: 'preserved',
    submissions_attrs: [{ submitters: submitters }],
    params: { 'send_email' => false, 'send_sms' => false }
  ).first
  created_submission = true
end

submitter = MerchantPortalDocumentSync.merchant_submitter_for(submission)
document = MerchantPortalDocumentSync.sync_submission(
  submission,
  combined,
  {
    merchant_id: merchant_id,
    template_name: template_name,
    sort_order: sort_order,
    artifact: {
      source: 'funding_portal_frpa_lod',
      template_id: combined.id,
      submission_id: submission.id,
      purchase_price: purchase_price.to_s('F'),
      purchased_amount: purchased_amount.to_s('F'),
      factor_rate: factor_rate.to_s('F'),
      specified_percentage: specified_percentage.to_s('F'),
      origination_fee: origination_fee.to_s('F')
    }
  },
  submitter
)

puts JSON.pretty_generate(
  ok: true,
  merchant_id: merchant_id,
  template_id: combined.id,
  submission_id: submission.id,
  submitter_id: submitter.id,
  submitter_slug: submitter.slug,
  merchant_document_id: document&.dig('id'),
  portal_url: submitter.preferences['portal_signing_url'],
  embed_src: document&.dig('embed_src'),
  created_template: created_template,
  created_submission: created_submission,
  signature_count: signature_count,
  document_count: combined.schema.size,
  terms: {
    purchase_price: purchase_price.to_s('F'),
    purchased_amount: purchased_amount.to_s('F'),
    factor_rate: factor_rate.to_s('F'),
    specified_percentage: specified_percentage.to_s('F'),
    origination_fee: origination_fee.to_s('F'),
    net_amount_funded: net_amount.to_s('F'),
    initial_periodic_amount: 'Variable'
  }
)
