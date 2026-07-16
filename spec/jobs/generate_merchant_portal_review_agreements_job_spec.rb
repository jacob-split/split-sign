# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateMerchantPortalReviewAgreementsJob do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:, author:) }
  let(:template) { create(:template, account:, author:, folder:, attachment_count: 0) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:redis_connection) { instance_double(RedisClient) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis_connection)
    allow(redis_connection).to receive(:call) do |command, *|
      command == 'SET' ? 'OK' : 1
    end
  end

  it 'loads the committed submissions and generates their review agreements' do
    expect(MerchantPortalReviewAgreementGenerator).to receive(:maybe_generate_for_portal_onboarding) do |submissions|
      expect(submissions.map(&:id)).to eq([submission.id])
    end

    described_class.new.perform('submission_ids' => [submission.id])
  end

  it 'reschedules instead of overlapping another review-agreement generation' do
    allow(redis_connection).to receive(:call).with(
      'SET',
      described_class::LOCK_KEY,
      kind_of(String),
      'NX',
      'EX',
      described_class::LOCK_TTL_SECONDS
    ).and_return(nil)

    expect(described_class).to receive(:perform_in).with(
      described_class::RETRY_DELAY_SECONDS,
      'submission_ids' => [submission.id]
    )
    expect(MerchantPortalReviewAgreementGenerator).not_to receive(:maybe_generate_for_portal_onboarding)

    described_class.new.perform('submission_ids' => [submission.id])
  end
end
