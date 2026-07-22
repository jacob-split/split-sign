# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MerchantPortalDocumentSync do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:, author:) }
  let(:template) { create(:template, account:, author:, folder:, attachment_count: 0) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:submitter) { submission.submitters.first }

  before do
    submitter.update!(metadata: { 'merchant_id' => 'merchant-123', 'source' => 'manual_send' })
    allow(SupabaseClient).to receive(:find_generated_docuseal_artifact).and_return(nil)
    allow(SupabaseClient).to receive(:find_merchant_for_document_context).and_return(nil)
    allow(SupabaseClient).to receive(:upsert_merchant_document).and_return([{ 'id' => 'doc-123' }])
    allow(MerchantPortalReviewAgreementGenerator).to receive(:maybe_generate_for_portal_onboarding)
  end

  it 'uses submitter metadata as the portal document context for manual/non-default sends' do
    documents = described_class.sync_submissions([submission], template:)

    expect(documents.size).to eq(1)
    expect(SupabaseClient).to have_received(:upsert_merchant_document).with(
      hash_including(
        merchant_id: 'merchant-123',
        template_id: template.id,
        submission_id: submission.id,
        status: 'pending'
      )
    )
    expect(submitter.reload.preferences['portal_signing_url']).to include('agreement=doc-123')
  end

  it 'projects the full Split Signature lifecycle for shared and embedded signing' do
    sent_at = 3.hours.ago
    opened_at = 2.hours.ago
    completed_at = 1.hour.ago
    submitter.update!(sent_at:, opened_at:, completed_at:)

    described_class.sync_submitter(submitter.reload)

    expect(SupabaseClient).to have_received(:upsert_merchant_document).with(
      hash_including(
        status: 'signed',
        sent_at: sent_at.iso8601,
        opened_at: opened_at.iso8601,
        signed_at: completed_at.iso8601,
        last_signature_event_at: completed_at.iso8601
      )
    )
  end

  it 'marks an incomplete past-due submission as expired' do
    submission.update!(expire_at: 1.minute.ago)

    described_class.sync_submitter(submitter.reload)

    expect(SupabaseClient).to have_received(:upsert_merchant_document).with(
      hash_including(status: 'expired', expired_at: submission.expire_at.iso8601)
    )
  end

  it 'queues portal review agreement generation instead of running it in the request' do
    job_class = class_double('GenerateMerchantPortalReviewAgreementsJob').as_stubbed_const
    submitter.update!(metadata: { 'merchant_id' => 'merchant-123', 'source' => 'merchant_portal_onboarding' })

    expect(job_class).to receive(:perform_async).with('submission_ids' => [submission.id])
    expect(MerchantPortalReviewAgreementGenerator).not_to receive(:maybe_generate_for_portal_onboarding)

    described_class.sync_submissions([submission], template:)
  end
end
