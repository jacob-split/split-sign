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
end
