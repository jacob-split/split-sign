# frozen_string_literal: true

require 'uri'

module MerchantPortalDocumentSync
  module_function

  def sync_submissions(submissions, template:, merchant_id: nil, template_name: nil)
    submissions = Array.wrap(submissions)
    base_context = build_context(template, merchant_id:, template_name:)

    documents = submissions.filter_map do |submission|
      submitter = merchant_submitter_for(submission)
      context = context_for_submitter(base_context, template, submitter)
      next unless context&.dig(:merchant_id).present?

      sync_submission(submission, template, context, submitter)
    end

    maybe_generate_review_agreements(submissions)

    documents
  end

  def sync_submitter(submitter)
    submission = submitter.submission
    template = submission.template
    return unless template

    context = context_for_submitter(build_context(template), template, submitter)
    return unless context&.dig(:merchant_id).present?

    sync_submission(submission, template, context, submitter)
  end

  def portal_url_for(submitter)
    submitter.preferences['portal_signing_url'].presence
  end

  def maybe_generate_review_agreements(submissions)
    submission_ids = Array.wrap(submissions).filter_map(&:id)
    return if submission_ids.empty?

    GenerateMerchantPortalReviewAgreementsJob.perform_async('submission_ids' => submission_ids)
  rescue StandardError => e
    Rails.logger.warn("[MerchantPortalDocumentSync] review agreement enqueue failed: #{e.class}: #{e.message}")
  end

  def archive_submission(submission, archived_at: Time.current)
    ControlPlaneClient.archive_merchant_document(submission.id, archived_at:)
  end

  def archive_template(template, archived_at: Time.current)
    ControlPlaneClient.archive_merchant_documents_for_template(template.id, archived_at:)
  end

  def unarchive_template(template)
    ControlPlaneClient.unarchive_merchant_documents_for_template(template.id)
  end

  def build_context(template, merchant_id: nil, template_name: nil)
    generated_context = ControlPlaneClient.find_generated_docuseal_artifact(template.id) || {}
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
    return context if submitter.blank?

    context = context.merge(context_from_submitter_metadata(submitter))
    return context if context[:merchant_id].present?

    merchant = ControlPlaneClient.find_merchant_for_document_context(
      email: submitter.email,
      name: merchant_name_from_template(template.name)
    )
    return context unless merchant

    context.merge(merchant_id: merchant['id'])
  end

  def context_from_submitter_metadata(submitter)
    metadata = submitter.metadata || {}
    {
      merchant_id: metadata['merchant_id'],
      merchant_identity_id: metadata['merchant_identity_id'],
      attio_company_id: metadata['attio_company_id'],
      attio_person_id: metadata['attio_person_id']
    }.compact
  end

  def sync_submission(submission, template, context, submitter = nil)
    submitter ||= merchant_submitter_for(submission)
    return unless submitter

    lifecycle = lifecycle_attributes(submission, submitter)
    document = ControlPlaneClient.upsert_merchant_document({
      merchant_id: context[:merchant_id],
      template_id: template.id,
      template_name: context[:template_name],
      submission_id: submitter.submission_id,
      embed_src: "#{Docuseal::CONSOLE_URL}/s/#{submitter.slug}",
      **lifecycle,
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

  def lifecycle_attributes(submission, submitter)
    expired_at = submission.expire_at if submission.expired? && !submitter.completed_at? && !submitter.declined_at?
    event_at = [
      submission.archived_at,
      submitter.completed_at,
      submitter.declined_at,
      expired_at,
      submitter.opened_at,
      submitter.sent_at
    ].compact.max || submitter.created_at

    {
      status: lifecycle_status(submission, submitter, expired_at:),
      sent_at: submitter.sent_at&.iso8601,
      opened_at: submitter.opened_at&.iso8601,
      signed_at: submitter.completed_at&.iso8601,
      declined_at: submitter.declined_at&.iso8601,
      expired_at: expired_at&.iso8601,
      last_signature_event_at: event_at&.iso8601
    }
  end

  def lifecycle_status(submission, submitter, expired_at: nil)
    return 'archived' if submission.archived_at?
    return 'signed' if submitter.completed_at?
    return 'declined' if submitter.declined_at?
    return 'expired' if expired_at
    return 'opened' if submitter.opened_at?
    return 'sent' if submitter.sent_at?

    'pending'
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
