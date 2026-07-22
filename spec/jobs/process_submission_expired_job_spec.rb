# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessSubmissionExpiredJob do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:, author:) }
  let(:template) { create(:template, account:, author:, folder:, attachment_count: 0) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author, expire_at: 1.minute.ago) }

  it 'syncs the portal document lifecycle before publishing expiration' do
    submitter = submission.submitters.first
    allow(MerchantPortalDocumentSync).to receive(:sync_submitter)
    allow(WebhookUrls).to receive(:enqueue_events)

    described_class.new.perform('submission_id' => submission.id)

    expect(MerchantPortalDocumentSync).to have_received(:sync_submitter).with(submitter)
    expect(WebhookUrls).to have_received(:enqueue_events).with(submission, 'submission.expired')
  end
end
