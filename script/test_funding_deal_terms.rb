# frozen_string_literal: true
require_relative '../lib/funding_deal_terms'

checks = 0
check = lambda do |condition, message|
  raise message unless condition
  checks += 1
end
rejected = lambda do |input|
  begin
    FundingDealTerms.parse!(input)
  rescue ArgumentError => error
    checks += 1
    next error.message
  end
  raise 'Unsafe funding inputs were accepted'
end
valid = {
  'purchase_price' => '10000.00', 'purchased_amount' => '12000.00', 'factor_rate' => '1.2',
  'origination_fee' => '100.00', 'prior_balance' => '500.00', 'ach_program_fee' => '25.00',
  'net_amount_funded' => '9375.00', 'specified_percentage' => '10', 'agreement_date' => '2026-09-26',
  'initial_periodic_amount' => 'Variable', 'terms_reference' => 'synthetic-unit-test-only'
}
FundingDealTerms::REQUIRED_FIELDS.each do |field|
  message = rejected.call(valid.reject { |key, _| key == field })
  check.call(message.include?(field), "Missing-input error did not identify #{field}")
end
terms = FundingDealTerms.parse!(valid)
check.call(terms['net_amount_funded'] == BigDecimal('9375.00'), 'Approved net amount changed')
check.call(terms['prior_balance'] == BigDecimal('500.00'), 'Approved prior balance changed')
check.call(terms['agreement_date'] == Date.new(2026, 9, 26), 'Approved date changed')
check.call(terms['initial_periodic_amount'] == 'Variable', 'Approved periodic amount changed')
[['purchase_price', 'NaN'], ['purchase_price', 'Infinity'], ['origination_fee', '-1'],
 ['ach_program_fee', '0.001'], ['purchase_price', '0'], ['factor_rate', '0.9'],
 ['specified_percentage', '101'], ['specified_percentage', '0'], ['purchased_amount', '9999'],
 ['net_amount_funded', '10001'], ['agreement_date', '2026-02-30'], ['agreement_date', 'today'],
 ['initial_periodic_amount', "Variable\nMaybe"], ['terms_reference', '']].each do |key, value|
  rejected.call(valid.merge(key => value))
end
source = File.read(File.join(__dir__, 'generate_merchant_funding_agreement.rb'))
check.call(source.index('FundingDealTerms.parse!') < source.index('Template.active'), 'Input validation occurs after model access')
check.call(source.index('combined.submissions.exists?') < source.index('Templates::Clone.call'), 'Issued packet protection occurs after a write')
check.call(!source.include?("config.fetch('agreement_date',"), 'Agreement date still defaults')
check.call(!source.include?("config.fetch('origination_fee',"), 'Origination fee still defaults')
check.call(!source.include?("'priorbalance' => '0.00'"), 'Prior balance still defaults')
puts "Funding deal preflight: #{checks} assertions passed"
