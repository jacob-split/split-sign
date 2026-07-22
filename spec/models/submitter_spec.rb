# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Submitter do
  it 'queues a portal lifecycle sync when a signature event changes' do
    account = create(:account)
    author = create(:user, account:)
    folder = create(:template_folder, account:, author:)
    template = create(:template, account:, author:, folder:, attachment_count: 0)
    submission = create(:submission, template:, created_by_user: author)
    submitter = create(:submitter, submission:, uuid: SecureRandom.uuid)

    expect do
      submitter.update!(opened_at: Time.current)
    end.to change(SyncMerchantPortalDocumentLifecycleJob.jobs, :size).by(1)

    expect(SyncMerchantPortalDocumentLifecycleJob.jobs.last['args']).to eq([{ 'submitter_id' => submitter.id }])
  end
end
