# frozen_string_literal: true

class MerchantNotificationMailer < ApplicationMailer
  ADMIN_RECIPIENTS = %w[jacob@split-llc.com blake@split-llc.com mel@support.split-llc.com].freeze

  def signing_complete(merchant_name:, merchant_email:, documents:)
    @merchant_name = merchant_name
    @merchant_email = merchant_email
    @documents = documents

    mail(
      to: ADMIN_RECIPIENTS,
      subject: "#{merchant_name} — All Documents Signed"
    )
  end
end
