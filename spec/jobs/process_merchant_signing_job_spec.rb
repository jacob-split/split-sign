# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessMerchantSigningJob do
  subject(:job) { described_class.new }

  it 'does not complete an SMS-gated agreement until SMS proof is persisted' do
    document = {
      'status' => 'signed',
      'signed_at' => '2026-07-29T12:00:00Z',
      'requires_sms_verification' => true,
      'sms_verified_at' => nil
    }

    expect(job.send(:completed_document?, document)).to be(false)
  end

  it 'accepts an SMS-gated agreement after signing and SMS proof' do
    document = {
      'status' => 'signed',
      'requires_sms_verification' => true,
      'sms_verified_at' => '2026-07-29T12:01:00Z'
    }

    expect(job.send(:completed_document?, document)).to be(true)
  end

  it 'preserves completion semantics for legacy agreements without an SMS gate' do
    document = {
      'status' => 'signed',
      'requires_sms_verification' => false,
      'sms_verified_at' => nil
    }

    expect(job.send(:completed_document?, document)).to be(true)
  end
end
