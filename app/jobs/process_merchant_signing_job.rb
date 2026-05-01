# frozen_string_literal: true

class ProcessMerchantSigningJob
  include Sidekiq::Job

  SIGNED_DOCUMENT_STATUSES = %w[signed completed].freeze

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])
    merchant_id = submitter.metadata&.dig('merchant_id')

    return unless merchant_id.present?

    signed_at = submitter.completed_at || Time.current

    SupabaseClient.update_merchant_document(
      submitter.submission_id,
      { signed_at: signed_at.iso8601, status: 'signed' }
    )

    active_docs = SupabaseClient.fetch_active_merchant_documents(merchant_id)
    all_signed = active_docs.present? && active_docs.all? { |doc| signed_document?(doc) }

    if all_signed
      mark_merchant_complete(merchant_id)

      merchant = SupabaseClient.fetch_merchant(merchant_id)

      MerchantNotificationMailer.signing_complete(
        merchant_name: merchant['business_name'],
        merchant_email: merchant['email'],
        documents: active_docs.map { |d| { name: d['template_name'], signed_at: d['signed_at'] } }
      ).deliver_later!
    end
  rescue SupabaseClient::Error => e
    Rails.logger.error("[ProcessMerchantSigningJob] Supabase error for submitter #{params['submitter_id']}: #{e.message}")
  end

  private

  def signed_document?(document)
    document['signed_at'].present? || SIGNED_DOCUMENT_STATUSES.include?(document['status'].to_s)
  end

  def mark_merchant_complete(merchant_id)
    SupabaseClient.update_merchant(merchant_id, { onboarding_status: 'complete', stage: 'in_review' })
  rescue SupabaseClient::Error => e
    raise unless e.message.match?(/stage/i)

    SupabaseClient.update_merchant(merchant_id, { onboarding_status: 'complete' })
  end
end
