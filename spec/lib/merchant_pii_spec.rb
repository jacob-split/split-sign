# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/merchant_pii'

RSpec.describe MerchantPii do
  let(:key) { OpenSSL::Random.random_bytes(32) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PII_ENCRYPTION_KEY').and_return(Base64.strict_encode64(key))
  end

  def encrypt(value)
    cipher = OpenSSL::Cipher.new(described_class::ALGORITHM)
    cipher.encrypt
    cipher.key = key
    iv = OpenSSL::Random.random_bytes(described_class::IV_LENGTH)
    cipher.iv = iv
    ciphertext = cipher.update(value) + cipher.final
    payload = iv + ciphertext + cipher.auth_tag(described_class::AUTH_TAG_LENGTH)
    "#{described_class::ENCRYPTION_PREFIX}#{Base64.strict_encode64(payload)}"
  end

  it 'decrypts all encrypted merchant banking and tax fields' do
    merchant = {
      'ein' => encrypt('12-3456789'),
      'bank_name' => encrypt('Example Credit Union'),
      'bank_routing_number' => encrypt('123456789'),
      'bank_account_number' => encrypt('123456789012')
    }

    described_class.decrypt_merchant(merchant)

    expect(merchant).to include(
      'ein' => '12-3456789',
      'bank_name' => 'Example Credit Union',
      'bank_routing_number' => '123456789',
      'bank_account_number' => '123456789012'
    )
  end
end
