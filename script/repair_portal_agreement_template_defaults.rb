# frozen_string_literal: true

# Repairs portal master mappings without changing operator-configured values.
# Dry-run by default. Run with APPLY=1 through `rails runner`.

template_field_names = {
  128 => %w[
    voice_authorization_fee
    batch_fee
    chargeback_fee
    pci_noncompliance_fee_monthly
    pre_arbitration_fee
    pci_fee_monthly
    cb_reversal_fee
    monthly_minimum
    avs_fee
    per_item_fee
  ],
  129 => ['LEASE_PAYMENT_p2_2', 'Lease Payment']
}.freeze

updates = template_field_names.to_h do |template_id, field_names|
  template = Template.find(template_id)
  fields = Array(template.fields).map(&:deep_dup)
  matched = []

  fields.each do |field|
    next unless field_names.include?(field['name'])

    raise "#{field['name']} has no configured template default" if field['default_value'].blank?

    field['preferences'] = (field['preferences'] || {}).merge(
      'data_path' => 'constant.template_default'
    )
    matched << field['name']
  end

  missing = field_names - matched
  raise "Template #{template_id} is missing fields: #{missing.join(', ')}" if missing.any?

  [template_id, [template, fields, matched]]
end

if ENV['APPLY'] == '1'
  Template.transaction do
    updates.each_value do |template, fields, _matched|
      template.update!(fields: fields)
    end
  end
  puts "updated=#{updates.values.sum { |_template, _fields, matched| matched.length }}"
else
  puts "dry_run=#{updates.values.sum { |_template, _fields, matched| matched.length }}"
end
