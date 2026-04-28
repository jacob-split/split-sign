# frozen_string_literal: true

module Api
  class SubmissionsController < ApiBaseController
    load_and_authorize_resource :template, only: :create
    load_and_authorize_resource :submission, only: %i[show index destroy]

    before_action only: :create do
      authorize!(:create, Submission)
    end

    def index
      submissions = Submissions.search(current_user, @submissions, params[:q])
      submissions = filter_submissions(submissions, params)

      submissions = paginate(submissions.preload(:created_by_user, :submitters,
                                                 template: { folder: :parent_folder },
                                                 combined_document_attachment: :blob,
                                                 audit_trail_attachment: :blob))

      expires_at = Accounts.link_expires_at(current_account)

      render json: {
        data: submissions.map do |s|
          Submissions::SerializeForApi.call(s, s.submitters, params,
                                            with_events: false, with_documents: false, with_values: false, expires_at:)
        end,
        pagination: {
          count: submissions.size,
          next: submissions.last&.id,
          prev: submissions.first&.id
        }
      }
    end

    def show
      submitters = @submission.submitters.preload(documents_attachments: :blob, attachments_attachments: :blob)

      submitters.each do |submitter|
        if submitter.completed_at? && submitter.documents_attachments.blank?
          submitter.documents_attachments = Submissions::EnsureResultGenerated.call(submitter)
        end
      end

      if @submission.audit_trail_attachment.blank? && submitters.all?(&:completed_at?)
        @submission.audit_trail_attachment = Submissions::EnsureAuditGenerated.call(@submission)
      end

      render json: Submissions::SerializeForApi.call(@submission, submitters, params)
    end

    def create
      Params::SubmissionCreateValidator.call(params)

      return render json: { error: 'Template not found' }, status: :unprocessable_content if @template.nil?

      if @template.fields.blank?
        Rollbar.warning("Template does not contain fields: #{@template.id}") if defined?(Rollbar)

        return render json: { error: 'Template does not contain fields' }, status: :unprocessable_content
      end

      params[:send_email] = true unless params.key?(:send_email)
      params[:send_sms] = false unless params.key?(:send_sms)

      submissions = create_submissions(@template, params)

      MerchantPortalDocumentSync.sync_submissions(submissions, template: @template)

      WebhookUrls.enqueue_events(submissions, 'submission.created')

      Submissions.send_signature_requests(submissions)

      submissions.each do |submission|
        submission.submitters.each do |submitter|
          next unless submitter.completed_at?

          ProcessSubmitterCompletionJob.perform_async('submitter_id' => submitter.id, 'send_invitation_email' => false)
        end
      end

      SearchEntries.enqueue_reindex(submissions)

      render json: build_create_json(submissions)
    rescue Submitters::NormalizeValues::BaseError, Submissions::CreateFromSubmitters::BaseError,
           DownloadUtils::UnableToDownload => e
      Rollbar.warning(e) if defined?(Rollbar)

      render json: { error: e.message }, status: :unprocessable_content
    end

    def create_from_document
      authorize!(:create, Template)
      authorize!(:create, Submission)

      if params[:documents].blank?
        return render json: { error: 'documents are required' }, status: :unprocessable_content
      end

      if params[:submitters].blank?
        return render json: { error: 'submitters are required' }, status: :unprocessable_content
      end

      template = Template.new
      template.account = current_account
      template.author = current_user
      template.source = 'api'
      template.name = params[:name].presence || 'Untitled'
      template.folder = TemplateFolders.find_or_create_by_name(current_user, nil)

      Templates.maybe_assign_access(template)
      template.save!

      documents = Array.wrap(params[:documents]).map do |doc_params|
        file = build_document_file(doc_params)
        Templates::CreateAttachments.handle_pdf_or_image(template, file, nil, params, extract_fields: true)
      end.flatten

      schema = documents.map { |doc| { attachment_uuid: doc.uuid, name: doc.filename.base } }

      if template.fields.blank?
        template.fields = Templates::ProcessDocument.normalize_attachment_fields(template, documents)
        schema.each { |item| item['pending_fields'] = true } if template.fields.present?
      end

      build_document_fields(template, documents) if params[:documents]&.any? { |d| d[:fields].present? }

      template.update!(schema:)

      if params[:flatten].in?([true, 'true'])
        template.preferences['flatten'] = true
        template.save!
      end

      if params[:remove_tags].in?([false, 'false'])
        template.preferences['remove_tags'] = false
        template.save!
      end

      if params[:merge_documents].in?([true, 'true']) && documents.size > 1
        merged = PdfUtils.merge(documents.map { |d| StringIO.new(d.download) })
        blob = ActiveStorage::Blob.create_and_upload!(
          io: merged, filename: "#{template.name}.pdf", content_type: 'application/pdf'
        )
        doc = template.documents.create!(blob:)
        Templates::ProcessDocument.call(doc, merged.string)
        template.schema = [{ attachment_uuid: doc.uuid, name: template.name }]
        template.fields.each { |f| f['areas']&.each { |a| a['attachment_uuid'] = doc.uuid } }
        template.save!
      end

      if params[:template_ids].present?
        Array.wrap(params[:template_ids]).each do |tid|
          extra = current_account.templates.find_by(id: tid)
          next unless extra

          extra.schema_documents.preload(:blob).each do |edoc|
            template.schema << { attachment_uuid: edoc.uuid, name: edoc.filename.base }
          end
          extra.fields.each { |f| template.fields << f }
          extra.submitters.each do |sub|
            unless template.submitters.any? { |s| s['name'] == sub['name'] }
              template.submitters << sub
            end
          end
          template.save!
        end
      end

      WebhookUrls.enqueue_events(template, 'template.created')
      SearchEntries.enqueue_reindex(template)

      if template.fields.blank?
        return render json: { error: 'Template does not contain fields' }, status: :unprocessable_content
      end

      params[:send_email] = true unless params.key?(:send_email)
      params[:send_sms] = false unless params.key?(:send_sms)

      @template = template
      submissions = create_submissions(template, params)

      MerchantPortalDocumentSync.sync_submissions(submissions, template:)

      WebhookUrls.enqueue_events(submissions, 'submission.created')
      Submissions.send_signature_requests(submissions)

      submissions.each do |submission|
        submission.submitters.each do |submitter|
          next unless submitter.completed_at?

          ProcessSubmitterCompletionJob.perform_async('submitter_id' => submitter.id, 'send_invitation_email' => false)
        end
      end

      SearchEntries.enqueue_reindex(submissions)

      render json: build_create_json(submissions)
    rescue Templates::CreateAttachments::PdfEncrypted
      render json: { error: 'PDF is encrypted' }, status: :unprocessable_content
    rescue Submitters::NormalizeValues::BaseError, Submissions::CreateFromSubmitters::BaseError,
           DownloadUtils::UnableToDownload => e
      Rollbar.warning(e) if defined?(Rollbar)
      render json: { error: e.message }, status: :unprocessable_content
    end

    def destroy
      if params[:permanently].in?(['true', true])
        @submission.destroy!
      else
        @submission.update!(archived_at: Time.current)

        WebhookUrls.enqueue_events(@submission, 'submission.archived')
      end

      render json: @submission.as_json(only: %i[id archived_at])
    end

    private

    def filter_submissions(submissions, params)
      submissions = submissions.where(template_id: params[:template_id]) if params[:template_id].present?
      submissions = submissions.where(slug: params[:slug]) if params[:slug].present?

      if params[:template_folder].present?
        folders =
          TemplateFolders.filter_by_full_name(TemplateFolder.accessible_by(current_ability), params[:template_folder])

        submissions = submissions.joins(:template).where(template: { folder_id: folders.pluck(:id) })
      end

      if params.key?(:archived)
        submissions = params[:archived].in?(['true', true]) ? submissions.archived : submissions.active
      end

      Submissions::Filter.call(submissions, current_user, params)
    end

    def build_create_json(submissions)
      json = submissions.flat_map do |submission|
        submission.submitters.map do |s|
          Submitters::SerializeForApi.call(s, with_documents: false, with_urls: true, params:)
        end
      end

      if request.path.ends_with?('/init')
        json =
          if submissions.size == 1
            {
              id: submissions.first.id,
              submitters: json,
              expire_at: submissions.first.expire_at,
              created_at: submissions.first.created_at
            }
          else
            { submitters: json }
          end
      end

      json
    end

    def create_submissions(template, params)
      is_send_email = !params[:send_email].in?(['false', false])

      if (emails = (params[:emails] || params[:email]).presence) &&
         params[:submission].blank? && params[:submitters].blank?
        Submissions.create_from_emails(template:,
                                       user: current_user,
                                       source: :api,
                                       mark_as_sent: is_send_email,
                                       emails:,
                                       params:)
      else
        submissions_attrs, attachments =
          Submissions::NormalizeParamUtils.normalize_submissions_params!(submissions_params, template)

        submissions = Submissions.create_from_submitters(
          template:,
          user: current_user,
          source: :api,
          submitters_order: params[:submitters_order] || params[:order] || 'preserved',
          submissions_attrs:,
          params:
        )

        submitters = submissions.flat_map(&:submitters)

        Submissions::NormalizeParamUtils.save_default_value_attachments!(attachments, submitters)

        submitters.each do |submitter|
          SubmissionEvents.create_with_tracking_data(submitter, 'api_complete_form', request) if submitter.completed_at?
        end

        submissions
      end
    end

    def build_document_file(doc_params)
      file_data = doc_params[:file]
      filename = doc_params[:name].presence || 'document.pdf'

      if file_data.blank?
        raise ActionController::ParameterMissing, 'documents[][file] is required'
      end

      if file_data.start_with?('http://') || file_data.start_with?('https://')
        resp = DownloadUtils.call(file_data)
        tempfile = Tempfile.new(filename)
        tempfile.binmode
        tempfile.write(resp.body)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile:, filename:, type: Marcel::MimeType.for(tempfile, name: filename)
        )
      else
        decoded = Base64.decode64(file_data)
        tempfile = Tempfile.new(filename)
        tempfile.binmode
        tempfile.write(decoded)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile:, filename:, type: Marcel::MimeType.for(tempfile, name: filename)
        )
      end
    end

    def build_document_fields(template, documents)
      fields = []
      submitter_uuid = template.submitters.first['uuid']

      Array.wrap(params[:documents]).each_with_index do |doc_params, doc_index|
        next if doc_params[:fields].blank?

        attachment = documents[doc_index]
        next unless attachment

        doc_params[:fields].each do |field_params|
          role = field_params[:role]
          sub_uuid = if role.present?
                       sub = template.submitters.find { |s| s['name'] == role }
                       unless sub
                         sub = { 'name' => role, 'uuid' => SecureRandom.uuid }
                         template.submitters << sub
                       end
                       sub['uuid']
                     else
                       submitter_uuid
                     end

          field = {
            'uuid' => SecureRandom.uuid,
            'submitter_uuid' => sub_uuid,
            'name' => field_params[:name] || field_params[:type]&.capitalize || 'Field',
            'type' => field_params[:type] || 'text',
            'required' => field_params[:required].in?([true, 'true', nil]),
            'preferences' => (field_params[:preferences] || {}).to_unsafe_h.stringify_keys
          }

          field['title'] = field_params[:title] if field_params[:title].present?
          field['description'] = field_params[:description] if field_params[:description].present?

          if field_params[:areas].present?
            field['areas'] = Array.wrap(field_params[:areas]).map do |area_params|
              {
                'x' => area_params[:x].to_f, 'y' => area_params[:y].to_f,
                'w' => area_params[:w].to_f, 'h' => area_params[:h].to_f,
                'page' => area_params[:page].to_i - 1,
                'attachment_uuid' => attachment.uuid
              }.compact
            end
          end

          fields << field
        end
      end

      template.fields = fields if fields.present?
    end

    def submissions_params
      permitted_attrs = [
        :send_email, :send_sms, :bcc_completed, :completed_redirect_url, :reply_to, :go_to_last,
        :require_phone_2fa, :require_email_2fa, :expire_at, :name,
        {
          variables: {},
          message: %i[subject body],
          submitters: [[:send_email, :send_sms, :completed_redirect_url, :uuid, :name, :email, :role,
                        :completed, :phone, :application_key, :external_id, :reply_to, :go_to_last,
                        :require_phone_2fa, :require_email_2fa, :order, :index, :invite_by,
                        { metadata: {}, values: {}, roles: [], readonly_fields: [], message: %i[subject body],
                          fields: [:name, :uuid, :default_value, :value, :title, :description,
                                   :readonly, :required, :validation_pattern, :invalid_message,
                                   { default_value: [], value: [], preferences: {}, validation: {} }] }]]
        }
      ]

      if params.key?(:submitters)
        params.permit(*permitted_attrs)
      else
        key = params.key?(:submission) ? :submission : :submissions

        params.permit(
          { key => [permitted_attrs] }, { key => permitted_attrs }
        ).fetch(key, [])
      end
    end
  end
end
