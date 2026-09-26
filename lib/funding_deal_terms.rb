# frozen_string_literal: true

require 'bigdecimal'
require 'date'

# Input validation only. This does not calculate an APR, choose disclosure law,
# or certify provider approval. Financial values must come from the referenced deal.
module FundingDealTerms
  CURRENCY_FIELDS = %w[purchase_price purchased_amount origination_fee prior_balance ach_program_fee net_amount_funded].freeze
  REQUIRED_FIELDS = (CURRENCY_FIELDS + %w[factor_rate specified_percentage agreement_date initial_periodic_amount terms_reference]).freeze
  module_function

  def parse!(config)
    raise ArgumentError, 'Funding configuration must be an object' unless config.is_a?(Hash)
    missing = REQUIRED_FIELDS.select { |key| !config.key?(key) || config[key].nil? || config[key].to_s.strip.empty? }
    raise ArgumentError, "Explicit funding inputs required: #{missing.join(', ')}" unless missing.empty?

    terms = {}
    (CURRENCY_FIELDS + %w[factor_rate specified_percentage]).each do |key|
      begin
        amount = BigDecimal(config.fetch(key).to_s)
      rescue ArgumentError
        raise ArgumentError, "#{key} must be a finite decimal"
      end
      raise ArgumentError, "#{key} must be a finite nonnegative decimal" unless amount.finite? && amount >= 0
      if CURRENCY_FIELDS.include?(key) && amount.round(2) != amount
        raise ArgumentError, "#{key} must be an explicit amount in whole cents"
      end
      terms[key] = amount
    end
    raise ArgumentError, 'purchase_price must be positive' unless terms['purchase_price'].positive?
    raise ArgumentError, 'factor_rate must be at least 1.0' unless terms['factor_rate'] >= 1
    unless terms['specified_percentage'].positive? && terms['specified_percentage'] <= 100
      raise ArgumentError, 'specified_percentage must be between 0 and 100'
    end
    unless terms['purchased_amount'] == (terms['purchase_price'] * terms['factor_rate']).round(2)
      raise ArgumentError, 'purchased_amount does not match the supplied purchase_price and factor_rate'
    end
    if terms['net_amount_funded'] > terms['purchase_price']
      raise ArgumentError, 'net_amount_funded cannot exceed purchase_price'
    end
    date = config.fetch('agreement_date')
    unless date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      raise ArgumentError, 'agreement_date must be an explicit YYYY-MM-DD date'
    end
    begin
      terms['agreement_date'] = Date.iso8601(date)
    rescue Date::Error
      raise ArgumentError, 'agreement_date is invalid'
    end
    %w[initial_periodic_amount terms_reference].each do |key|
      value = config.fetch(key)
      unless value.is_a?(String) && !value.strip.empty? && value.length <= 1_000 && !value.match?(/[\r\n]/)
        raise ArgumentError, "#{key} must be explicit single-line text"
      end
      terms[key] = value.strip
    end
    terms.freeze
  end
end
