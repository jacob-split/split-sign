# frozen_string_literal: true

require 'rails_helper'
require 'smtp_environment_config'

RSpec.describe SmtpEnvironmentConfig do
  it 'does not configure SMTP when the host is blank' do
    expect(described_class.build('SMTP_ADDRESS' => '  ')).to be_nil
  end

  it 'builds authenticated STARTTLS settings with bounded timeouts' do
    settings = described_class.build(
      'SMTP_ADDRESS' => 'smtp.resend.com',
      'SMTP_PORT' => '587',
      'SMTP_DOMAIN' => 'split-llc.com',
      'SMTP_USERNAME' => 'resend',
      'SMTP_PASSWORD' => 'existing-api-key',
      'SMTP_AUTHENTICATION' => 'plain',
      'SMTP_ENABLE_STARTTLS' => 'true',
      'SMTP_OPEN_TIMEOUT' => '8',
      'SMTP_READ_TIMEOUT' => '12'
    )

    expect(settings).to include(
      address: 'smtp.resend.com',
      port: 587,
      domain: 'split-llc.com',
      user_name: 'resend',
      password: 'existing-api-key',
      authentication: 'plain',
      enable_starttls: true,
      open_timeout: 8,
      read_timeout: 12,
      openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER
    )
  end

  it 'omits authentication when no password is configured' do
    settings = described_class.build('SMTP_ADDRESS' => 'smtp.internal.test')

    expect(settings).not_to have_key(:authentication)
    expect(settings).not_to have_key(:password)
  end
end
