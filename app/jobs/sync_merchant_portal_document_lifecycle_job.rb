# frozen_string_literal: true

class SyncMerchantPortalDocumentLifecycleJob
  include Sidekiq::Job

  sidekiq_options retry: 10

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])

    MerchantPortalDocumentSync.sync_submitter(submitter)
  end
end
