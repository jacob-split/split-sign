# frozen_string_literal: true

require 'openssl'

module SmtpEnvironmentConfig
  module_function

  def build(env = ENV)
    address = present_value(env['SMTP_ADDRESS'])
    return if address.nil?

    password = present_value(env['SMTP_PASSWORD'])

    {
      address:,
      port: integer_value(env['SMTP_PORT'], 587),
      domain: present_value(env['SMTP_DOMAIN']),
      user_name: present_value(env['SMTP_USERNAME']),
      password:,
      openssl_verify_mode: env['SMTP_SSL_VERIFY'] == 'false' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER,
      authentication: password ? present_value(env['SMTP_AUTHENTICATION']) || 'plain' : nil,
      enable_starttls: env['SMTP_ENABLE_STARTTLS'] != 'false',
      open_timeout: integer_value(env['SMTP_OPEN_TIMEOUT'], 15),
      read_timeout: integer_value(env['SMTP_READ_TIMEOUT'], 25)
    }.compact
  end

  def present_value(value)
    value = value.to_s.strip
    value unless value.empty?
  end
  private_class_method :present_value

  def integer_value(value, default)
    Integer(present_value(value) || default.to_s, 10)
  end
  private_class_method :integer_value
end
