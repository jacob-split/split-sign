# frozen_string_literal: true

class MerchantNotificationMailer < ApplicationMailer
  def signing_complete(merchant_name:, merchant_email:, documents:)
    @merchant_name = merchant_name
    @merchant_email = merchant_email
    @documents = documents

    mail(
      to: 'jacob@split-llc.com',
      subject: "#{merchant_name} — All Documents Signed"
    )
  end
end
