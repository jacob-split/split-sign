# frozen_string_literal: true

require 'uri'

module MerchantPortalDocumentSync
  module_function

  def sync_submissions(submissions, template:, merchant_id: nil, template_name: nil)
    base_context = build_context(template, merchant_id:, template_name:)

    Array.wrap(submissions).filter_map do |submission|
      submitter = merchant_submitter_for(submission)
      context = context_for_submitter(base_context, template, submitter)
      next unless context&.dig(:merchant_id).present?

      sync_submission(submission, template, context, submitter)
    end
  rescue SupabaseClient::Error => e
    Rails.logger.warn("[MerchantPortalDocumentSync] Supabase sync failed: #{e.message}")
    []
  end

  def portal_url_for(submitter)
    submitter.preferences['portal_signing_url'].presence
  end

  def archive_submission(submission, archived_at: Time.current)
    SupabaseClient.archive_merchant_document(submission.id, archived_at:)
  rescue SupabaseClient::Error => e
    Rails.logger.warn("[MerchantPortalDocumentSync] Supabase archive sync failed: #{e.message}")
  end

  def archive_template(template, archived_at: Time.current)
    SupabaseClient.archive_merchant_documents_for_template(template.id, archived_at:)
  rescue SupabaseClient::Error => e
    Rails.logger.warn("[MerchantPortalDocumentSync] Supabase template archive sync failed: #{e.message}")
  end

  def unarchive_template(template)
    SupabaseClient.unarchive_merchant_documents_for_template(template.id)
  rescue SupabaseClient::Error => e
    Rails.logger.warn("[MerchantPortalDocumentSync] Supabase template restore sync failed: #{e.message}")
  end

  def build_context(template, merchant_id: nil, template_name: nil)
    generated_context = SupabaseClient.find_generated_docuseal_artifact(template.id) || {}
    {
      merchant_id: merchant_id.presence || generated_context[:merchant_id],
      merchant_identity_id: generated_context[:merchant_identity_id],
      attio_company_id: generated_context[:attio_company_id],
      attio_person_id: generated_context[:attio_person_id],
      template_name: template_name.presence || generated_context[:template_name].presence || template.name,
      sort_order: generated_context[:sort_order],
      artifact: generated_context[:artifact]
    }.compact
  end

  def context_for_submitter(context, template, submitter)
    return context if context[:merchant_id].present? || submitter.blank?

    merchant = SupabaseClient.find_merchant_for_document_context(
      email: submitter.email,
      name: merchant_name_from_template(template.name)
    )
    return context unless merchant

    context.merge(merchant_id: merchant['id'])
  end

  def sync_submission(submission, template, context, submitter = nil)
    submitter ||= merchant_submitter_for(submission)
    return unless submitter

    document = SupabaseClient.upsert_merchant_document({
      merchant_id: context[:merchant_id],
      template_id: template.id,
      template_name: context[:template_name],
      submission_id: submitter.submission_id,
      embed_src: "#{Docuseal::CONSOLE_URL}/s/#{submitter.slug}",
      signed_at: submitter.completed_at&.iso8601,
      status: submitter.completed_at? ? 'signed' : 'pending',
      archived_at: submission.archived_at&.iso8601,
      sort_order: context[:sort_order]
    }).first

    portal_url = merchant_portal_url(document&.dig('id') || submitter.submission_id)
    preferences = submitter.preferences.merge(
      'only_required_fields' => false,
      'portal_signing_url' => portal_url
    )

    submitter.update!(
      metadata: submitter.metadata.merge(submitter_metadata(context)).compact,
      preferences:
    )

    document
  end

  def submitter_metadata(context)
    {
      'merchant_id' => context[:merchant_id],
      'merchant_identity_id' => context[:merchant_identity_id],
      'attio_company_id' => context[:attio_company_id],
      'attio_person_id' => context[:attio_person_id]
    }
  end

  def merchant_submitter_for(submission)
    submitters = submission.submitters.to_a
    submitters.find { |submitter| submitter_role(submission, submitter).match?(/first party|merchant|owner/i) } ||
      submitters.find { |submitter| submitter.email.to_s.exclude?('@split-llc.com') } ||
      submitters.first
  end

  def submitter_role(submission, submitter)
    template_submitters = submission.template_submitters || submission.template.submitters
    template_submitters.find { |item| item['uuid'] == submitter.uuid }&.dig('name').to_s
  end

  def merchant_name_from_template(template_name)
    normalized = template_name.to_s.sub(/\A(MPA|MLA|INSTALL|FRPA|LOD)[^_]*_?/i, '')
    normalized = normalized.sub(/\A(payroc|epi|sub|tcg|exec|maverick|mav)_/i, '')
    normalized.tr('_-', ' ').squish.presence
  end

  def merchant_portal_url(document_id)
    base = ENV.fetch('MERCHANT_PORTAL_URL', 'https://www.split-llc.com/portal/dashboard/')
    uri = URI.parse(base)
    query = Rack::Utils.parse_nested_query(uri.query)
    query['tab'] = 'agreements'
    query['agreement'] = document_id.to_s
    uri.query = query.to_query
    uri.to_s
  end
end
