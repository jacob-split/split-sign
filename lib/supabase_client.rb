# frozen_string_literal: true

require 'net/http'
require 'json'
require 'zlib'
require 'stringio'

module SupabaseClient
  Error = Class.new(StandardError)

  module_function

  def fetch_merchants(query)
    return [] if query.blank?

    escaped = query.gsub('%', '\\%').gsub('_', '\\_')
    pattern = "%#{escaped}%"

    # Search by business_name, dba_name, or email
    params = {
      'or' => "(business_name.ilike.#{pattern},dba_name.ilike.#{pattern},email.ilike.#{pattern})",
      'select' => 'id,business_name,dba_name,email,phone,onboarding_status',
      'order' => 'business_name.asc',
      'limit' => '20'
    }

    get('/rest/v1/merchants', params)
  end

  def fetch_merchant(id)
    results = get('/rest/v1/merchants', { 'id' => "eq.#{id}", 'select' => '*' })

    raise Error, "Merchant not found: #{id}" if results.empty?

    results.first
  end

  def fetch_principals(merchant_id)
    get('/rest/v1/principals', {
      'merchant_id' => "eq.#{merchant_id}",
      'select' => '*',
      'order' => 'created_at.asc'
    })
  end

  def fetch_template_field_mappings(template_id)
    rows = get('/rest/v1/template_field_mappings', {
      'template_id' => "eq.#{template_id}",
      'select' => 'mappings,agent_only_fields'
    })

    rows.first
  end

  def insert_merchant_document(attrs)
    post('/rest/v1/merchant_documents', attrs)
  end

  def upsert_merchant_document(attrs)
    merchant_id = attrs[:merchant_id] || attrs['merchant_id']
    template_id = attrs[:template_id] || attrs['template_id']
    raise Error, 'merchant_id is required' if merchant_id.blank?
    raise Error, 'template_id is required' if template_id.blank?

    existing = get('/rest/v1/merchant_documents', {
      'merchant_id' => "eq.#{merchant_id}",
      'template_id' => "eq.#{template_id}",
      'archived_at' => 'is.null',
      'select' => 'id',
      'order' => 'updated_at.desc',
      'limit' => '1'
    })

    body = attrs.compact.merge(updated_at: Time.current.iso8601)
    body[:signed_at] = attrs[:signed_at] if attrs.key?(:signed_at)
    body['signed_at'] = attrs['signed_at'] if attrs.key?('signed_at')

    if existing.any?
      patch('/rest/v1/merchant_documents', body, { 'id' => "eq.#{existing.first['id']}" })
    else
      post('/rest/v1/merchant_documents', body)
    end
  end

  def update_merchant(id, attrs)
    patch("/rest/v1/merchants", attrs, { 'id' => "eq.#{id}" })
  end

  def update_merchant_document(submission_id, attrs)
    patch('/rest/v1/merchant_documents', attrs.compact.merge(updated_at: Time.current.iso8601),
          { 'submission_id' => "eq.#{submission_id}" })
  end

  def archive_merchant_document(submission_id, archived_at: Time.current)
    update_merchant_document(submission_id, {
      status: 'archived',
      archived_at: archived_at&.iso8601
    })
  end

  def archive_merchant_documents_for_template(template_id, archived_at: Time.current)
    patch('/rest/v1/merchant_documents', {
      archived_at: archived_at&.iso8601,
      updated_at: Time.current.iso8601
    }, { 'template_id' => "eq.#{template_id}", 'archived_at' => 'is.null' })
  end

  def unarchive_merchant_documents_for_template(template_id)
    patch('/rest/v1/merchant_documents', {
      archived_at: nil,
      updated_at: Time.current.iso8601
    }, { 'template_id' => "eq.#{template_id}" })
  end

  def upsert_template_field_mappings(template_id, data_paths, agent_only_fields = [], template_name: nil)
    mappings_json = data_paths.map do |field_name, data_path|
      { fieldName: field_name, dataPath: data_path, isAutoMapped: false }
    end

    existing = get('/rest/v1/template_field_mappings', {
      'template_id' => "eq.#{template_id}",
      'select' => 'id'
    })

    if existing.any?
      patch('/rest/v1/template_field_mappings', {
        mappings: mappings_json,
        agent_only_fields: agent_only_fields
      }, { 'template_id' => "eq.#{template_id}" })
    else
      post('/rest/v1/template_field_mappings', {
        template_id: template_id,
        template_name: template_name || "Template #{template_id}",
        mappings: mappings_json,
        agent_only_fields: agent_only_fields
      })
    end
  end

  def fetch_merchant_documents(merchant_id)
    get('/rest/v1/merchant_documents', {
      'merchant_id' => "eq.#{merchant_id}",
      'select' => '*',
      'order' => 'created_at.asc'
    })
  end

  def fetch_active_merchant_documents(merchant_id)
    get('/rest/v1/merchant_documents', {
      'merchant_id' => "eq.#{merchant_id}",
      'archived_at' => 'is.null',
      'select' => '*',
      'order' => 'created_at.asc'
    })
  end

  def find_generated_docuseal_artifact(template_id)
    rows = get('/rest/v1/merchant_sync_events', {
      'select' => 'merchant_identity_id,supabase_merchant_id,payload,created_at,event_type',
      'event_type' => 'eq.docuseal_artifacts_generated',
      'order' => 'created_at.desc',
      'limit' => '300'
    })

    rows.each do |row|
      payload = row['payload'] || {}
      artifacts = payload['docuseal_artifacts'] || []
      artifacts.each_with_index do |artifact, index|
        next unless artifact['template_id'].to_s == template_id.to_s

        return {
          merchant_id: row['supabase_merchant_id'] || payload['supabase_merchant_id'],
          merchant_identity_id: row['merchant_identity_id'] || payload['merchant_identity_id'],
          attio_company_id: payload['attio_company_id'],
          attio_person_id: payload['attio_person_id'],
          template_name: artifact['master_template'] || payload['docuseal_template_name'],
          sort_order: index,
          artifact: artifact
        }.compact
      end
    end

    nil
  end

  def find_merchant_for_document_context(email: nil, name: nil)
    if email.present?
      rows = get('/rest/v1/merchants', {
        'or' => "(email.eq.#{email},business_email.eq.#{email})",
        'select' => 'id,business_name,dba_name,email,business_email',
        'limit' => '2'
      })
      return rows.first if rows.any?
    end

    if name.present?
      pattern = "%#{name.gsub('%', '\\%').gsub('_', '\\_')}%"
      rows = get('/rest/v1/merchants', {
        'or' => "(business_name.ilike.#{pattern},dba_name.ilike.#{pattern})",
        'select' => 'id,business_name,dba_name,email,business_email',
        'limit' => '2'
      })
      return rows.first if rows.one?
    end

    nil
  end

  # HTTP helpers

  def get(path, params = {})
    uri = build_uri(path, params)
    request = Net::HTTP::Get.new(uri)
    add_headers(request)
    execute(uri, request)
  end

  def post(path, body)
    uri = build_uri(path)
    request = Net::HTTP::Post.new(uri)
    add_headers(request)
    request['Prefer'] = 'return=representation'
    request.body = body.to_json
    execute(uri, request)
  end

  def delete(path, params = {})
    uri = build_uri(path, params)
    request = Net::HTTP::Delete.new(uri)
    add_headers(request)
    execute(uri, request)
  end

  def patch(path, body, params = {})
    uri = build_uri(path, params)
    request = Net::HTTP::Patch.new(uri)
    add_headers(request)
    request['Prefer'] = 'return=representation'
    request.body = body.to_json
    execute(uri, request)
  end

  def build_uri(path, params = {})
    url = "#{supabase_url}#{path}"
    url += "?#{URI.encode_www_form(params)}" if params.any?
    URI.parse(url)
  end

  def add_headers(request)
    request['apikey'] = service_role_key
    request['Authorization'] = "Bearer #{service_role_key}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
  end

  def execute(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 15

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Supabase API error (#{response.code}): #{response.body}"
    end

    body = decode_body(response)
    JSON.parse(body)
  rescue JSON::ParserError
    []
  end

  def decode_body(response)
    case response['content-encoding']
    when 'gzip'
      Zlib::GzipReader.new(StringIO.new(response.body)).read
    when 'deflate'
      Zlib::Inflate.inflate(response.body)
    else
      response.body
    end
  end

  def supabase_url
    ENV.fetch('SUPABASE_URL') { raise Error, 'SUPABASE_URL not configured' }
  end

  def service_role_key
    ENV.fetch('SUPABASE_SERVICE_ROLE_KEY') { raise Error, 'SUPABASE_SERVICE_ROLE_KEY not configured' }
  end
end
