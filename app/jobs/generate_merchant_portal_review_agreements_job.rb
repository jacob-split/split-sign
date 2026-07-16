# frozen_string_literal: true

require 'securerandom'

class GenerateMerchantPortalReviewAgreementsJob
  include Sidekiq::Job

  LOCK_KEY = 'split:merchant_portal:review_agreement_generation'
  LOCK_TTL_SECONDS = 30 * 60
  RETRY_DELAY_SECONDS = 5
  RELEASE_LOCK_SCRIPT = <<~LUA.freeze
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('del', KEYS[1])
    end
    return 0
  LUA

  sidekiq_options retry: 5

  def perform(params = {})
    submission_ids = Array(params['submission_ids']).filter_map do |value|
      Integer(value, exception: false)
    end.select(&:positive?)
    return if submission_ids.empty?

    with_generation_lock(params) do
      submissions = Submission.where(id: submission_ids).includes(:created_by_user, :template, :submitters)
      MerchantPortalReviewAgreementGenerator.maybe_generate_for_portal_onboarding(submissions)
    end
  end

  private

  def with_generation_lock(params)
    lock_token = SecureRandom.uuid
    acquired = Sidekiq.redis do |connection|
      connection.call('SET', LOCK_KEY, lock_token, 'NX', 'EX', LOCK_TTL_SECONDS)
    end

    unless acquired
      self.class.perform_in(RETRY_DELAY_SECONDS, params)
      return
    end

    yield
  ensure
    release_generation_lock(lock_token) if acquired
  end

  def release_generation_lock(lock_token)
    Sidekiq.redis do |connection|
      connection.call('EVAL', RELEASE_LOCK_SCRIPT, 1, LOCK_KEY, lock_token)
    end
  rescue StandardError => e
    Rails.logger.warn("[GenerateMerchantPortalReviewAgreementsJob] lock release failed: #{e.class}: #{e.message}")
  end
end
