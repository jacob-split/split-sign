# frozen_string_literal: true

module MerchantFieldMapper
  INTERACTIVE_TYPES = Set.new(%w[signature initials stamp image file]).freeze

  # ────────────────────────────────────────────────────────
  # Portal Fields — single source of truth for builder sidebar,
  # auto-detect naming, and merchant data resolution.
  # ────────────────────────────────────────────────────────

  PORTAL_FIELDS = [
    # Business Identity
    { section: 'Business Identity', display_name: 'DBA Name', type: 'text', data_path: 'merchant.dba_name' },
    { section: 'Business Identity', display_name: 'Legal Business Name', type: 'text', data_path: 'merchant.business_name' },
    { section: 'Business Identity', display_name: 'EIN / Tax ID', type: 'text', data_path: 'merchant.ein' },
    { section: 'Business Identity', display_name: 'Business Type', type: 'text', data_path: 'merchant.company_type' },
    { section: 'Business Identity', display_name: 'Industry / Products', type: 'text', data_path: 'merchant.product_description' },
    { section: 'Business Identity', display_name: 'Website', type: 'text', data_path: 'merchant.website' },

    # Business Contact
    { section: 'Business Contact', display_name: 'Business Phone', type: 'text', data_path: 'merchant.phone' },
    { section: 'Business Contact', display_name: 'Business Email', type: 'text', data_path: 'merchant.email' },
    { section: 'Business Contact', display_name: 'Business Address', type: 'text', data_path: 'merchant.street' },
    { section: 'Business Contact', display_name: 'City', type: 'text', data_path: 'merchant.city' },
    { section: 'Business Contact', display_name: 'State', type: 'text', data_path: 'merchant.state' },
    { section: 'Business Contact', display_name: 'Zip Code', type: 'text', data_path: 'merchant.zip' },
    { section: 'Business Contact', display_name: 'City/State/Zip', type: 'text', data_path: 'computed.biz_city_state_zip' },

    # Financial
    { section: 'Financial', display_name: 'Monthly Volume', type: 'text', data_path: 'computed.monthly_volume_formatted' },
    { section: 'Financial', display_name: 'Annual Volume', type: 'text', data_path: 'computed.annual_cc_volume' },
    { section: 'Financial', display_name: 'Average Ticket', type: 'text', data_path: 'computed.average_ticket_formatted' },
    { section: 'Financial', display_name: 'High Ticket', type: 'text', data_path: 'computed.high_ticket_formatted' },
    { section: 'Financial', display_name: 'Card Present %', type: 'text', data_path: 'computed.card_present_pct' },
    { section: 'Financial', display_name: 'E-Commerce %', type: 'text', data_path: 'computed.ecommerce_pct' },
    { section: 'Financial', display_name: 'MOTO %', type: 'text', data_path: 'computed.moto_pct' },
    { section: 'Financial', display_name: 'Business Start Date', type: 'date', data_path: 'computed.business_start_date_formatted' },
    { section: 'Financial', display_name: 'Annual Revenue', type: 'text', data_path: 'computed.annual_revenue_formatted' },

    # Banking
    { section: 'Banking', display_name: 'Routing Number', type: 'text', data_path: 'merchant.bank_routing_number' },
    { section: 'Banking', display_name: 'Account Number', type: 'text', data_path: 'merchant.bank_account_number' },
    { section: 'Banking', display_name: 'Bank Name', type: 'text', data_path: 'merchant.bank_name' },

    # Principal / Owner
    { section: 'Principal / Owner', display_name: 'Owner Full Name', type: 'text', data_path: 'computed.owner_name' },
    { section: 'Principal / Owner', display_name: 'First Name', type: 'text', data_path: 'principal.first_name' },
    { section: 'Principal / Owner', display_name: 'Last Name', type: 'text', data_path: 'principal.last_name' },
    { section: 'Principal / Owner', display_name: 'Title', type: 'text', data_path: 'computed.title' },
    { section: 'Principal / Owner', display_name: 'Ownership %', type: 'number', data_path: 'computed.ownership_pct' },
    { section: 'Principal / Owner', display_name: 'SSN', type: 'text', data_path: 'principal.ssn' },
    { section: 'Principal / Owner', display_name: 'Date of Birth', type: 'date', data_path: 'computed.dob_formatted' },
    { section: 'Principal / Owner', display_name: "Driver's License #", type: 'text', data_path: 'principal.drivers_license_number' },
    { section: 'Principal / Owner', display_name: 'DL State', type: 'text', data_path: 'principal.drivers_license_state' },
    { section: 'Principal / Owner', display_name: 'Owner Phone', type: 'text', data_path: 'principal.phone' },
    { section: 'Principal / Owner', display_name: 'Home Address', type: 'text', data_path: 'principal.street' },
    { section: 'Principal / Owner', display_name: 'Home City', type: 'text', data_path: 'principal.city' },
    { section: 'Principal / Owner', display_name: 'Home State', type: 'text', data_path: 'principal.state' },
    { section: 'Principal / Owner', display_name: 'Home Zip', type: 'text', data_path: 'principal.zip' },
    { section: 'Principal / Owner', display_name: 'Owner City/State/Zip', type: 'text', data_path: 'computed.owner_city_state_zip' }
  ].freeze

  module_function

  def portal_fields_for_builder
    PORTAL_FIELDS.map do |pf|
      { name: pf[:display_name], type: pf[:type], title: pf[:display_name],
        section: pf[:section], preferences: { data_path: pf[:data_path] } }
    end
  end

  # ────────────────────────────────────────────────────────
  # Helpers
  # ────────────────────────────────────────────────────────

  def format_city_state_zip(city, state, zip)
    parts = [city, state].compact_blank.join(', ')
    zip.present? ? "#{parts} #{zip}" : parts
  end

  def to_mmddyyyy(date_str)
    return '' if date_str.blank?

    if (match = date_str.match(/^(\d{4})-(\d{2})-(\d{2})/))
      "#{match[2]}/#{match[3]}/#{match[1]}"
    else
      date_str
    end
  end

  def today_mmddyyyy
    Time.current.strftime('%m/%d/%Y')
  end

  def format_currency(val)
    return '' if val.nil?

    "$#{number_with_delimiter(val.to_i)}"
  end

  def number_with_delimiter(number)
    number.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
  end

  def pct_or_default(val, default = '0')
    val.nil? ? default : val.to_s
  end

  # ────────────────────────────────────────────────────────
  # Canonical Field Map for fuzzy auto-mapping
  #
  # Each entry: [search_terms, data_path, accessor_lambda]
  #   - search_terms: normalized phrases to fuzzy-match against field names
  #   - data_path: the canonical path to save in template_field_mappings
  #   - accessor: lambda(merchant, principal) → resolved value
  # ────────────────────────────────────────────────────────

  CANONICAL_FIELD_MAP = [
    # Business identity
    [%w[dba doing\ business\ as dba\ name trade\ name],
     'merchant.dba_name', ->(m, _p) { m['dba_name'].presence || m['business_name'] }],
    [%w[legal\ name legal\ business\ name business\ name company\ name corporate\ name],
     'merchant.business_name', ->(m, _p) { m['business_name'] }],
    [%w[ein tax\ id taxpayer\ identification federal\ tax\ id fein],
     'merchant.ein', ->(m, _p) { m['ein'] }],
    [%w[business\ type company\ type entity\ type type\ of\ business],
     'merchant.company_type', ->(m, _p) { m['company_type'] || '' }],
    [%w[industry type\ of\ products products\ services nature\ of\ business business\ description],
     'merchant.product_description', ->(m, _p) { m['product_description'].presence || m['industry'] || '' }],
    [%w[website url web\ address merchant\ website],
     'merchant.website', ->(m, _p) { m['website'] || '' }],

    # Business contact
    [%w[business\ phone telephone\ number phone\ number business\ telephone dba\ phone],
     'merchant.phone', ->(m, _p) { m['phone'] }],
    [%w[business\ email email\ address contact\ email merchant\ email],
     'merchant.email', ->(m, _p) { m['email'] }],
    [%w[business\ address street\ address dba\ address business\ street street],
     'merchant.street', ->(m, _p) { m['street'] }],
    [%w[business\ city city],
     'merchant.city', ->(m, _p) { m['city'] }],
    [%w[business\ state state],
     'merchant.state', ->(m, _p) { m['state'] }],
    [%w[business\ zip zip zip\ code postal\ code],
     'merchant.zip', ->(m, _p) { m['zip'] }],
    [%w[contact\ name contact\ person dba\ contact],
     'computed.contact_name', ->(m, _p) { m['contact_name'] || '' }],

    # Financial
    [%w[monthly\ volume average\ monthly\ volume gross\ volume monthly\ sales],
     'computed.monthly_volume_formatted', ->(m, _p) { format_currency(m['monthly_volume']) }],
    [%w[annual\ volume annual\ cc\ volume yearly\ volume],
     'computed.annual_cc_volume', ->(m, _p) { format_currency((m['monthly_volume'] || 0).to_i * 12) }],
    [%w[average\ ticket average\ transaction avg\ charge avg\ transaction\ amount],
     'computed.average_ticket_formatted', ->(m, _p) { format_currency(m['average_ticket']) }],
    [%w[high\ ticket highest\ transaction highest\ charge max\ transaction],
     'computed.high_ticket_formatted', ->(m, _p) { format_currency(m['high_ticket']) }],
    [%w[card\ present emv swiped in\ store trans\ store],
     'computed.card_present_pct', ->(m, _p) { pct_or_default(m['card_present_pct']) }],
    [%w[ecommerce internet online trans\ web],
     'computed.ecommerce_pct', ->(m, _p) { pct_or_default(m['ecommerce_pct']) }],
    [%w[moto telephone\ order phone\ order trans\ phone mail\ order],
     'computed.moto_pct', ->(m, _p) { pct_or_default(m['moto_pct']) }],
    [%w[business\ start\ date date\ started start\ date bus\ start\ date],
     'computed.business_start_date_formatted', ->(m, _p) { to_mmddyyyy(m['business_start_date']) }],
    [%w[annual\ revenue],
     'computed.annual_revenue_formatted', ->(m, _p) { format_currency(m['annual_revenue']) }],

    # Banking
    [%w[routing aba transit routing\ number aba\ routing],
     'merchant.bank_routing_number', ->(m, _p) { m['bank_routing_number'] || '' }],
    [%w[account\ number account bank\ account dda\ number],
     'merchant.bank_account_number', ->(m, _p) { m['bank_account_number'] || '' }],
    [%w[bank\ name financial\ institution],
     'merchant.bank_name', ->(m, _p) { m['bank_name'] || '' }],

    # Principal / Owner
    [%w[owner\ name principal\ name guarantor\ name print\ name signer\ name],
     'computed.owner_name', ->(_m, p) { "#{p['first_name']} #{p['last_name']}".strip }],
    [%w[first\ name owner\ first\ name],
     'principal.first_name', ->(_m, p) { p['first_name'] }],
    [%w[last\ name owner\ last\ name],
     'principal.last_name', ->(_m, p) { p['last_name'] }],
    [%w[title owner\ title],
     'computed.title', ->(_m, p) { p['title'].presence || 'Owner' }],
    [%w[ownership ownership\ pct equity owner\ equity percent\ ownership],
     'computed.ownership_pct', ->(_m, p) { (p['ownership_pct'] || 100).to_s }],
    [%w[ssn social\ security owner\ ss social],
     'principal.ssn', ->(_m, p) { p['ssn'] }],
    [%w[date\ of\ birth dob owner\ dob birth\ date],
     'computed.dob_formatted', ->(_m, p) { to_mmddyyyy(p['dob']) }],
    [%w[drivers\ license dl\ number license\ number owner\ dl],
     'principal.drivers_license_number', ->(_m, p) { p['drivers_license_number'] }],
    [%w[dl\ state license\ state owner\ dl\ state],
     'principal.drivers_license_state', ->(_m, p) { p['drivers_license_state'] || '' }],
    [%w[owner\ phone cell\ phone cell\ number mobile\ number personal\ phone],
     'principal.phone', ->(_m, p) { p['phone'] || '' }],
    [%w[home\ address owner\ address home\ street residential\ address],
     'principal.street', ->(_m, p) { p['street'] || '' }],
    [%w[home\ city owner\ city],
     'principal.city', ->(_m, p) { p['city'] || '' }],
    [%w[home\ state owner\ state],
     'principal.state', ->(_m, p) { p['state'] || '' }],
    [%w[home\ zip owner\ zip],
     'principal.zip', ->(_m, p) { p['zip'] || '' }],
    [%w[home\ phone owner\ home\ phone],
     'principal.home_phone', ->(_m, p) { p['home_phone'] || '' }],

    # Composite address fields
    [%w[city\ state\ zip business\ city\ state],
     'computed.biz_city_state_zip', ->(m, _p) { format_city_state_zip(m['city'], m['state'], m['zip']) }],
    [%w[owner\ city\ state\ zip home\ city\ state],
     'computed.owner_city_state_zip', ->(_m, p) { format_city_state_zip(p['city'], p['state'], p['zip']) }],

    # Date fields
    [%w[date today current\ date signature\ date],
     'computed.today', ->(_m, _p) { today_mmddyyyy }]
  ].freeze

  # ────────────────────────────────────────────────────────
  # Fuzzy matching
  # ────────────────────────────────────────────────────────

  def normalize_field_name(name)
    return '' if name.blank?

    name
      .gsub(/([a-z])([A-Z])/, '\1 \2')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
      .downcase
      .gsub(/[^a-z0-9\s]/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end

  def match_score(normalized_field, search_term)
    return 1.0 if normalized_field == search_term

    if normalized_field.include?(search_term)
      coverage = search_term.length.to_f / normalized_field.length
      return 0.5 + coverage * 0.4
    end

    if search_term.include?(normalized_field) && normalized_field.length > 2
      coverage = normalized_field.length.to_f / search_term.length
      return 0.3 + coverage * 0.3
    end

    field_words = normalized_field.split(' ').reject(&:empty?)
    term_words = search_term.split(' ').reject(&:empty?)
    overlap = term_words.select { |w| field_words.include?(w) }

    if overlap.any? && overlap.length >= term_words.length * 0.5
      return 0.4 + (overlap.length.to_f / [field_words.length, term_words.length].max) * 0.3
    end

    0
  end

  # ────────────────────────────────────────────────────────
  # Auto-map: returns { values:, data_paths: }
  #   values   = { "FieldName" => "resolved value", ... }
  #   data_paths = { "FieldName" => "merchant.email", ... }
  # ────────────────────────────────────────────────────────

  def build_auto_field_map(merchant, principal, template_fields)
    values = {}
    data_paths = {}

    template_fields.each do |field|
      next if INTERACTIVE_TYPES.include?(field['type'])
      next if field['name'].blank?

      normalized = normalize_field_name(field['name'])
      best_score = 0
      best_entry = nil

      CANONICAL_FIELD_MAP.each do |search_terms, data_path, accessor|
        search_terms.each do |term|
          score = match_score(normalized, term)
          if score > best_score
            best_score = score
            best_entry = [data_path, accessor]
          end
        end
      end

      next unless best_score >= 0.5 && best_entry

      data_path, accessor = best_entry
      value = accessor.call(merchant, principal)
      if value.present?
        values[field['name']] = value
        data_paths[field['name']] = data_path
      end
    end

    { values: values, data_paths: data_paths }
  end

  # ────────────────────────────────────────────────────────
  # Saved mapping resolution
  # ────────────────────────────────────────────────────────

  def resolve_data_path(data_path, merchant, principal)
    return '' if data_path.blank? || data_path == 'agent_only' || data_path == 'unmappable'

    parts = data_path.split('.', 2)
    source = parts[0]
    key = parts[1]

    if source == 'computed'
      resolve_computed(key, merchant, principal)
    elsif source == 'principal'
      val = principal&.dig(key)
      val.nil? ? '' : val
    else
      val = merchant&.dig(key)
      val.nil? ? '' : val
    end
  end

  def resolve_computed(key, merchant, principal)
    case key
    when 'owner_name'
      "#{principal['first_name']} #{principal['last_name']}".strip
    when 'contact_name'
      merchant['contact_name'].presence || "#{principal['first_name']} #{principal['last_name']}".strip
    when 'title'
      principal['title'].presence || 'Owner'
    when 'ownership_pct'
      (principal['ownership_pct'] || 100).to_s
    when 'today'
      today_mmddyyyy
    when 'dob_formatted'
      to_mmddyyyy(principal['dob'])
    when 'business_start_date_formatted'
      to_mmddyyyy(merchant['business_start_date'])
    when 'biz_city_state_zip'
      format_city_state_zip(merchant['city'], merchant['state'], merchant['zip'])
    when 'owner_city_state_zip'
      format_city_state_zip(principal['city'], principal['state'], principal['zip'])
    when 'monthly_volume_formatted'
      format_currency(merchant['monthly_volume'])
    when 'annual_cc_volume'
      format_currency((merchant['monthly_volume'] || 0).to_i * 12)
    when 'average_ticket_formatted'
      format_currency(merchant['average_ticket'])
    when 'high_ticket_formatted'
      format_currency(merchant['high_ticket'])
    when 'annual_revenue_formatted'
      format_currency(merchant['annual_revenue'])
    when 'card_present_pct'
      pct_or_default(merchant['card_present_pct'])
    when 'ecommerce_pct'
      pct_or_default(merchant['ecommerce_pct'])
    when 'moto_pct'
      pct_or_default(merchant['moto_pct'])
    when 'internet_pct'
      [0, 100 - (merchant['card_present_pct'] || 0).to_i - (merchant['moto_pct'] || 0).to_i].max.to_s
    when 'biz_address_city'
      [merchant['street'], merchant['city']].compact_blank.join(', ')
    when 'equipment_location'
      [merchant['street'], merchant['city'], merchant['state'], merchant['zip']].compact_blank.join(', ')
    when 'equipment_name'
      equipment = merchant['equipment_info'] || {}
      equipment['model'].presence || equipment['make'].presence || ''
    else
      ''
    end
  end

  # ────────────────────────────────────────────────────────
  # Main entry point
  #
  # Priority: saved mappings → auto-map
  # Returns { values:, agent_only_fields:, data_paths:, source: }
  # ────────────────────────────────────────────────────────

  def get_field_map_for_template(template_id, merchant, principal, template_fields, saved_record = nil)
    # 1. Saved mappings (from template_field_mappings table in Supabase)
    # saved_record is a single hash: { "mappings" => [...], "agent_only_fields" => [...] }
    if saved_record.present? && saved_record['mappings'].present?
      values = {}
      agent_only_fields = saved_record['agent_only_fields'] || []
      data_paths = {}

      saved_record['mappings'].each do |mapping|
        field_name = mapping['fieldName']
        data_path = mapping['dataPath']
        next if field_name.blank? || data_path.blank?

        resolved = resolve_data_path(data_path, merchant, principal)
        values[field_name] = resolved if resolved.present?
        data_paths[field_name] = data_path
      end

      return { values: values, agent_only_fields: agent_only_fields, data_paths: data_paths, source: :saved }
    end

    # 2. Auto-map (fuzzy matching for any template)
    auto_result = build_auto_field_map(merchant, principal, template_fields)

    {
      values: auto_result[:values],
      agent_only_fields: [],
      data_paths: auto_result[:data_paths],
      source: :auto
    }
  end
end
