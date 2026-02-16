# frozen_string_literal: true

class ProcessMerchantSigningJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])
    merchant_id = submitter.metadata&.dig('merchant_id')

    return unless merchant_id.present?

    # 1. Update this document's signed_at in Supabase
    SupabaseClient.update_merchant_document(
      submitter.submission_id,
      { signed_at: Time.current.iso8601, status: 'signed' }
    )

    # 2. Check if all documents for this merchant are signed
    all_docs = SupabaseClient.fetch_merchant_documents(merchant_id)
    all_signed = all_docs.present? && all_docs.all? { |doc| doc['signed_at'].present? }

    if all_signed
      # 3. Update merchant onboarding_status
      SupabaseClient.update_merchant(merchant_id, { onboarding_status: 'complete' })

      # 4. Send admin notification
      merchant = SupabaseClient.fetch_merchant(merchant_id)

      MerchantNotificationMailer.signing_complete(
        merchant_name: merchant['business_name'],
        merchant_email: merchant['email'],
        documents: all_docs.map { |d| { name: d['template_name'], signed_at: d['signed_at'] } }
      ).deliver_later!
    end
  rescue SupabaseClient::Error => e
    Rails.logger.error("[ProcessMerchantSigningJob] Supabase error for submitter #{params['submitter_id']}: #{e.message}")
  end
end
