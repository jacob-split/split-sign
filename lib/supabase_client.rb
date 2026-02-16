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
    get('/rest/v1/template_field_mappings', {
      'template_id' => "eq.#{template_id}",
      'select' => 'field_name,data_path,is_auto_mapped'
    })
  end

  def insert_merchant_document(attrs)
    post('/rest/v1/merchant_documents', attrs)
  end

  def update_merchant(id, attrs)
    patch("/rest/v1/merchants", attrs, { 'id' => "eq.#{id}" })
  end

  def update_merchant_document(submission_id, attrs)
    patch('/rest/v1/merchant_documents', attrs, { 'submission_id' => "eq.#{submission_id}" })
  end

  def upsert_template_field_mappings(template_id, mappings)
    # Delete existing mappings for this template, then insert new ones
    delete('/rest/v1/template_field_mappings', { 'template_id' => "eq.#{template_id}" })

    return if mappings.empty?

    rows = mappings.map do |field_name, data_path|
      {
        template_id: template_id,
        field_name: field_name,
        data_path: data_path,
        is_auto_mapped: false
      }
    end

    post('/rest/v1/template_field_mappings', rows)
  end

  def fetch_merchant_documents(merchant_id)
    get('/rest/v1/merchant_documents', {
      'merchant_id' => "eq.#{merchant_id}",
      'select' => '*',
      'order' => 'created_at.asc'
    })
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
