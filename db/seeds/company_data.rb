# frozen_string_literal: true

# Seeds COMPANY_INFO and COMPANY_PRINCIPALS into EncryptedConfig.
# Run via: rails runner db/seeds/company_data.rb
#
# On the server, remember to source .env first:
#   set -a && source .env && set +a && RAILS_ENV=production bundle exec rails runner db/seeds/company_data.rb

account = Account.first

company_info = {
  'business_name' => 'Split LLC',
  'dba_name' => '',
  'ein' => '41-2697737',
  'company_type' => 'LLC',
  'product_description' => 'Merchant services',
  'phone' => '',
  'email' => 'jacob@split-llc.com',
  'street' => '5540 Centerview Dr Ste 204 #503507',
  'city' => 'Raleigh',
  'state' => 'NC',
  'zip' => '27606',
  'business_start_date' => '2025-11-20',
  'website' => ''
}

company_principals = [
  {
    'id' => 'jacob',
    'first_name' => 'Jacob',
    'last_name' => 'Schulte',
    'title' => 'Managing Member',
    'ownership_pct' => 50,
    'email' => 'jacob@split-llc.com',
    'ssn' => '256-63-9855',
    'dob' => '1982-12-16',
    'drivers_license_number' => '26764525',
    'drivers_license_state' => 'NC',
    'phone' => '',
    'street' => '2081 Honeysuckle Vine Run',
    'city' => 'Winston Salem',
    'state' => 'NC',
    'zip' => '27106'
  },
  {
    'id' => 'blake',
    'first_name' => 'Blake',
    'last_name' => 'Craighead',
    'title' => 'Managing Member',
    'ownership_pct' => 50,
    'email' => 'blake@split-llc.com',
    'ssn' => '250-06-1820',
    'dob' => '1971-01-15',
    'drivers_license_number' => '',
    'drivers_license_state' => 'NC',
    'phone' => '704-975-4008',
    'street' => '11916 Bryton Pass Lane #2001',
    'city' => 'Huntersville',
    'state' => 'NC',
    'zip' => '28078'
  }
]

info_config = account.encrypted_configs.find_or_initialize_by(key: EncryptedConfig::COMPANY_INFO_KEY)
info_config.value = company_info
info_config.save!
puts "Saved COMPANY_INFO for account #{account.id}"

principals_config = account.encrypted_configs.find_or_initialize_by(key: EncryptedConfig::COMPANY_PRINCIPALS_KEY)
principals_config.value = company_principals
principals_config.save!
puts "Saved COMPANY_PRINCIPALS for account #{account.id} (#{company_principals.size} principals)"
