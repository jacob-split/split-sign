# frozen_string_literal: true

module Api
  class TemplatesController < ApiBaseController
    load_and_authorize_resource :template, except: [:create]

    def index
      templates = filter_templates(@templates, params)

      templates = paginate(templates.preload(:author, folder: :parent_folder))

      schema_documents =
        ActiveStorage::Attachment.where(record_id: templates.map(&:id),
                                        record_type: 'Template',
                                        name: :documents,
                                        uuid: templates.flat_map { |t| t.schema.pluck('attachment_uuid') })
                                 .preload(:blob)

      preview_image_attachments =
        ActiveStorage::Attachment.joins(:blob)
                                 .where(blob: { filename: ['0.png', '0.jpg'] })
                                 .where(record_id: schema_documents.map(&:id),
                                        record_type: 'ActiveStorage::Attachment',
                                        name: :preview_images)
                                 .preload(:blob)

      expires_at = Accounts.link_expires_at(current_account)

      render json: {
        data: templates.map do |t|
          Templates::SerializeForApi.call(t,
                                          schema_documents: schema_documents.select { |e| e.record_id == t.id },
                                          preview_image_attachments:,
                                          expires_at:)
        end,
        pagination: {
          count: templates.size,
          next: templates.last&.id,
          prev: templates.first&.id
        }
      }
    end

    def show
      render json: Templates::SerializeForApi.call(@template)
    end

    def create
      @template = Template.new
      @template.account = current_account
      @template.author = current_user
      @template.source = 'api'
      @template.name = params[:name].presence || 'Untitled'
      @template.external_id = params[:external_id] if params[:external_id].present?
      @template.shared_link = params[:shared_link] if params.key?(:shared_link)
      @template.folder = TemplateFolders.find_or_create_by_name(current_user, params[:folder_name])

      authorize!(:create, @template)

      Templates.maybe_assign_access(@template)

      @template.save!

      documents = Array.wrap(params[:documents]).map do |doc_params|
        file = build_file_from_params(doc_params)
        Templates::CreateAttachments.handle_pdf_or_image(@template, file, nil, params, extract_fields: true)
      end.flatten

      schema = documents.map { |doc| { attachment_uuid: doc.uuid, name: doc.filename.base } }

      if @template.fields.blank?
        @template.fields = Templates::ProcessDocument.normalize_attachment_fields(@template, documents)

        schema.each { |item| item['pending_fields'] = true } if @template.fields.present?
      end

      build_fields_from_params(documents) if params[:documents]&.any? { |d| d[:fields].present? }

      @template.update!(schema:)

      if params[:flatten].in?([true, 'true'])
        @template.preferences['flatten'] = true
        @template.save!
      end

      if params[:remove_tags].in?([false, 'false'])
        @template.preferences['remove_tags'] = false
        @template.save!
      end

      WebhookUrls.enqueue_events(@template, 'template.created')
      SearchEntries.enqueue_reindex(@template)

      render json: Templates::SerializeForApi.call(@template)
    rescue Templates::CreateAttachments::PdfEncrypted
      render json: { error: 'PDF is encrypted' }, status: :unprocessable_content
    rescue DownloadUtils::UnableToDownload => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def update
      if (folder_name = params[:folder_name] || params.dig(:template, :folder_name))
        @template.folder = TemplateFolders.find_or_create_by_name(current_user, folder_name)
      end

      Array.wrap(params[:roles].presence || params.dig(:template, :roles).presence).each_with_index do |role, index|
        if (item = @template.submitters[index])
          item['name'] = role
        else
          @template.submitters << { 'name' => role, 'uuid' => SecureRandom.uuid }
        end
      end

      archived = params.key?(:archived) ? params[:archived] : params.dig(:template, :archived)

      if archived.in?([true, false])
        @template.archived_at = archived == true ? Time.current : nil
      end

      @template.update!(template_params)

      SearchEntries.enqueue_reindex(@template)

      WebhookUrls.enqueue_events(@template, 'template.updated')

      render json: @template.as_json(only: %i[id updated_at])
    end

    def destroy
      if params[:permanently].in?(['true', true])
        @template.destroy!
      else
        @template.update!(archived_at: Time.current)
      end

      render json: @template.as_json(only: %i[id archived_at])
    end

    private

    def filter_templates(templates, params)
      templates = Templates.search(current_user, templates, params[:q])
      templates = params[:archived].in?(['true', true]) ? templates.archived : templates.active
      templates = templates.where(external_id: params[:application_key]) if params[:application_key].present?
      templates = templates.where(external_id: params[:external_id]) if params[:external_id].present?
      templates = templates.where(slug: params[:slug]) if params[:slug].present?

      if params[:folder].present?
        folders = TemplateFolders.filter_by_full_name(TemplateFolder.accessible_by(current_ability), params[:folder])

        templates = templates.where(folder_id: folders.pluck(:id))
      end

      templates
    end

    def build_file_from_params(doc_params)
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
          tempfile:,
          filename:,
          type: Marcel::MimeType.for(tempfile, name: filename)
        )
      else
        decoded = Base64.decode64(file_data)
        tempfile = Tempfile.new(filename)
        tempfile.binmode
        tempfile.write(decoded)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile:,
          filename:,
          type: Marcel::MimeType.for(tempfile, name: filename)
        )
      end
    end

    def build_fields_from_params(documents)
      fields = []
      submitter_uuid = @template.submitters.first['uuid']

      Array.wrap(params[:documents]).each_with_index do |doc_params, doc_index|
        next if doc_params[:fields].blank?

        attachment = documents[doc_index]
        next unless attachment

        doc_params[:fields].each do |field_params|
          role = field_params[:role]
          sub_uuid = if role.present?
                       sub = @template.submitters.find { |s| s['name'] == role }
                       unless sub
                         sub = { 'name' => role, 'uuid' => SecureRandom.uuid }
                         @template.submitters << sub
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

          if field_params[:validation].present?
            field['validation'] = field_params[:validation].to_unsafe_h.stringify_keys
          end

          if field_params[:options].present?
            field['options'] = Array.wrap(field_params[:options]).map do |opt|
              opt.is_a?(String) ? { 'value' => opt, 'uuid' => SecureRandom.uuid } : opt.to_unsafe_h.stringify_keys
            end
          end

          if field_params[:areas].present?
            field['areas'] = Array.wrap(field_params[:areas]).map do |area_params|
              {
                'x' => area_params[:x].to_f,
                'y' => area_params[:y].to_f,
                'w' => area_params[:w].to_f,
                'h' => area_params[:h].to_f,
                'page' => area_params[:page].to_i - 1,
                'attachment_uuid' => attachment.uuid
              }.compact
            end
          end

          fields << field
        end
      end

      @template.fields = fields if fields.present?
    end

    def template_params
      permitted_params = [
        :name,
        :external_id,
        :shared_link,
        {
          submitters: [%i[name uuid is_requester invite_by_uuid optional_invite_by_uuid linked_to_uuid email order]],
          fields: [[:uuid, :submitter_uuid, :name, :type,
                    :required, :readonly, :default_value,
                    :title, :description, :prefillable,
                    { preferences: {},
                      default_value: [],
                      conditions: [%i[field_uuid value action operation]],
                      options: [%i[value uuid]],
                      validation: %i[message pattern min max step],
                      areas: [%i[x y w h cell_w attachment_uuid option_uuid page]] }]]
        }
      ]

      if params.key?(:template)
        params.require(:template).permit(permitted_params)
      else
        params.permit(permitted_params)
      end
    end
  end
end
