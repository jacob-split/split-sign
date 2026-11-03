# frozen_string_literal: true

require 'rails_helper'

describe 'Portal packet generation and signing' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': author.access_token.token } }
  let(:merchant_id) { SecureRandom.uuid }

  before do
    allow(ControlPlaneClient).to receive(:find_generated_docuseal_artifact).and_return(nil)
    allow(ControlPlaneClient).to receive(:upsert_merchant_document).and_return([{ 'id' => SecureRandom.uuid }])
    create(:encrypted_config, key: EncryptedConfig::ESIGN_CERTS_KEY,
                              value: GenerateCertificate.call.transform_values(&:to_pem))
  end

  it 'retains prefills, requires proof, signs both agreements and synchronizes downloadable originals' do
    ['Onyx MPA', 'Private Client Lease Agreement'].each do |name|
      template = create(:template, account:, author:, name:)
      role = template.submitters.first
      field = template.fields.find { |item| item['submitter_uuid'] == role['uuid'] && item['type'] == 'text' }
      expect(field).to be_present
      post '/api/submissions', headers:, params: {
        template_id: template.id, send_email: false, send_sms: false,
        submitters: [{ role: role['name'], email: 'merchant@example.com', name: 'Test Merchant',
                      metadata: { merchant_id:, agreement_stack_key: 'onyx_private_client', requires_sms_verification: true },
                      fields: [{ uuid: field['uuid'], default_value: 'Portal Business LLC', readonly: true }] }]
      }.to_json
      expect(response).to have_http_status(:ok)
      signer = Submitter.find(response.parsed_body.first['id'])
      persisted = signer.submission.template_fields.find { |item| item['uuid'] == field['uuid'] }
      expect(persisted.values_at('default_value', 'readonly')).to eq(['Portal Business LLC', true])
      expect(signer.sent_at).to be_nil
      put "/api/submitters/#{signer.id}", headers:, params: { completed: true }.to_json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(signer.reload.completed_at).to be_nil

      %w[send_2fa_sms phone_verified complete_verification].each do |event_type|
        post "/api/submissions/#{signer.submission_id}/audit_events", headers:, params: {
          event_type:, data: { provider: 'telnyx_verify', channel: 'sms',
                              external_event_id: "fixture:#{signer.id}:#{event_type}",
                              telnyx_verification_id: 'isolated-provider-proof' }
        }.to_json
        expect(response).to have_http_status(:ok)
      end
      put "/api/submitters/#{signer.id}", headers:, params: { completed: true }.to_json
      expect(response).to have_http_status(:ok)
      expect(signer.reload.completed_at).to be_present
      ProcessSubmitterCompletionJob.new.perform('submitter_id' => signer.id)
      expect(signer.reload.documents).not_to be_empty
      expect(CompletedDocument.where(submitter_id: signer.id).first.sha256).to be_present
      expect(ControlPlaneClient).to have_received(:upsert_merchant_document)
        .with(hash_including(merchant_id:, submission_id: signer.submission_id, status: 'signed'))
    end
  end
end
