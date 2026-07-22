# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncMerchantPortalDocumentLifecycleJob do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:, author:) }
  let(:template) { create(:template, account:, author:, folder:, attachment_count: 0) }
  let(:submission) { create(:submission, template:, created_by_user: author) }
  let(:submitter) { create(:submitter, submission:, uuid: SecureRandom.uuid) }

  it 'replays the submitter through the shared portal lifecycle service' do
    allow(MerchantPortalDocumentSync).to receive(:sync_submitter)

    described_class.new.perform('submitter_id' => submitter.id)

    expect(MerchantPortalDocumentSync).to have_received(:sync_submitter).with(submitter)
  end
end
