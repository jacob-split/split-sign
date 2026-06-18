# frozen_string_literal: true

module Api
  class SubmissionAuditEventsController < ApiBaseController
    ALLOWED_EVENT_TYPES = %w[send_2fa_sms phone_verified complete_verification].freeze
    DATA_KEYS = %w[
      channel
      external_event_id
      ip
      merchant_document_id
      method
      phone
      provider
      provider_status
      telnyx_profile_id
      telnyx_response_code
      telnyx_verification_id
      ua
      user_agent
    ].freeze

    load_and_authorize_resource :submission

    def create
      event_type = params[:event_type].to_s
      return render json: { error: 'Unsupported event type' }, status: :unprocessable_content unless ALLOWED_EVENT_TYPES.include?(event_type)

      submitter = find_submitter
      return render json: { error: 'Submitter not found' }, status: :not_found if submitter.blank?

      data = audit_event_data
      update_submitter_phone(submitter, data['phone'])

      event = find_existing_event(event_type, data) ||
              @submission.submission_events.create!(
                submitter:,
                event_type:,
                data:,
                event_timestamp: event_timestamp
              )
      purge_generated_audit_files

      render json: {
        id: event.id,
        submission_id: event.submission_id,
        submitter_id: event.submitter_id,
        event_type: event.event_type,
        event_timestamp: event.event_timestamp
      }
    end

    private

    def find_submitter
      if params[:submitter_id].present?
        @submission.submitters.find_by(id: params[:submitter_id])
      else
        @submission.submitters.order(:id).first
      end
    end

    def audit_event_data
      raw_data =
        if params[:data].respond_to?(:permit)
          params[:data].permit(DATA_KEYS).to_h
        elsif params[:data].is_a?(Hash)
          params[:data].slice(*DATA_KEYS)
        else
          {}
        end

      raw_data.compact_blank
    end

    def event_timestamp
      return Time.current if params[:event_timestamp].blank?

      Time.zone.parse(params[:event_timestamp].to_s)
    rescue ArgumentError
      Time.current
    end

    def update_submitter_phone(submitter, phone)
      return if phone.blank?
      return if submitter.phone == phone

      submitter.update!(phone:)
    end

    def purge_generated_audit_files
      @submission.audit_trail_attachment&.purge
      @submission.combined_document_attachment&.purge
    end

    def find_existing_event(event_type, data)
      external_event_id = data['external_event_id']
      return if external_event_id.blank?

      @submission.submission_events.where(event_type:).find do |event|
        event.data['external_event_id'] == external_event_id
      end
    end
  end
end
