# frozen_string_literal: true

require 'openssl'
require 'base64'

module MerchantPii
  ENCRYPTION_PREFIX = 'ENC:v1:'
  ALGORITHM = 'aes-256-gcm'
  IV_LENGTH = 12
  AUTH_TAG_LENGTH = 16

  module_function

  def decrypt(value)
    return value if value.nil? || value.empty?
    return value unless value.start_with?(ENCRYPTION_PREFIX)

    payload_b64 = value[ENCRYPTION_PREFIX.length..]
    payload = Base64.decode64(payload_b64)

    iv = payload[0, IV_LENGTH]
    auth_tag = payload[-AUTH_TAG_LENGTH, AUTH_TAG_LENGTH]
    ciphertext = payload[IV_LENGTH..-(AUTH_TAG_LENGTH + 1)]

    decipher = OpenSSL::Cipher.new(ALGORITHM)
    decipher.decrypt
    decipher.key = encryption_key
    decipher.iv = iv
    decipher.auth_tag = auth_tag

    decrypted = decipher.update(ciphertext) + decipher.final
    decrypted.force_encoding('UTF-8')
  rescue OpenSSL::Cipher::CipherError => e
    Rails.logger.error("[MerchantPii] Decryption error: #{e.message}")
    '[DECRYPTION_ERROR]'
  end

  def encrypted?(value)
    value.is_a?(String) && value.start_with?(ENCRYPTION_PREFIX)
  end

  def decrypt_merchant(merchant)
    return unless merchant

    %w[ein bank_name bank_routing_number bank_account_number].each do |field|
      value = merchant[field]
      merchant[field] = decrypt(value) if value && (!value.respond_to?(:empty?) || !value.empty?)
    end

    merchant
  end

  def decrypt_principal(principal)
    return unless principal

    %w[ssn dob drivers_license_number].each do |field|
      value = principal[field]
      principal[field] = decrypt(value) if value && (!value.respond_to?(:empty?) || !value.empty?)
    end

    principal
  end

  def encryption_key
    key_b64 = ENV.fetch('PII_ENCRYPTION_KEY') do
      raise 'PII_ENCRYPTION_KEY not configured'
    end

    key = Base64.decode64(key_b64)

    unless key.bytesize == 32
      raise "PII_ENCRYPTION_KEY must be 32 bytes (got #{key.bytesize})"
    end

    key
  end
end
