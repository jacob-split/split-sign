# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessMerchantSigningJob do
  subject(:job) { described_class.new }

  it 'records portal signatures without completing the merchant or notifying admins' do
    completed_at = Time.utc(2026, 9, 24, 6, 48, 21)
    submitter = instance_double(
      Submitter,
      metadata: { 'merchant_id' => 'merchant-abc', 'source' => 'merchant_portal_onboarding' },
      completed_at:,
      submission_id: 242
    )
    allow(Submitter).to receive(:find).with(242).and_return(submitter)

    expect(ControlPlaneClient).to receive(:update_merchant_document).with(
      242,
      { signed_at: completed_at.iso8601, status: 'signed' }
    )
    expect(ControlPlaneClient).not_to receive(:fetch_active_merchant_documents)
    expect(ControlPlaneClient).not_to receive(:update_merchant)
    expect(MerchantNotificationMailer).not_to receive(:signing_complete)

    job.perform('submitter_id' => 242)
  end

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
