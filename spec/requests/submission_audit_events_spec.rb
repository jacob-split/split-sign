# frozen_string_literal: true

describe 'Submission audit events API' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:submitter) { submission.submitters.first }
  let(:headers) { { 'x-auth-token': author.access_token.token } }

  it 'records the complete SMS verification proof on the native submission audit log' do
    shared_data = {
      merchant_document_id: 'merchant-document-128',
      phone: '(***) ***-1212',
      provider: 'telnyx_verify',
      channel: 'sms',
      telnyx_profile_id: 'profile-1',
      telnyx_verification_id: 'verification-1',
      telnyx_response_code: 'accepted',
      provider_status: 'accepted',
      ip: '203.0.113.10',
      ua: 'Split portal test'
    }

    {
      'send_2fa_sms' => 'agreement_sms_sent:merchant-document-128:challenge-1',
      'phone_verified' => 'agreement_sms_phone_verified:merchant-document-128:verification-1',
      'complete_verification' => 'agreement_sms_complete_verification:merchant-document-128:verification-1'
    }.each do |event_type, external_event_id|
      post "/api/submissions/#{submission.id}/audit_events",
           headers:,
           params: {
             event_type:,
             event_timestamp: '2026-07-29T12:00:00.000Z',
             data: shared_data.merge(external_event_id:)
           }.to_json

      expect(response).to have_http_status(:ok)
    end

    events = submission.reload.submission_events.order(:id)
    expect(events.pluck(:event_type)).to eq(%w[send_2fa_sms phone_verified complete_verification])
    expect(events.map { |event| event.data['merchant_document_id'] }.uniq).to eq(['merchant-document-128'])
    expect(events.map { |event| event.data['provider'] }.uniq).to eq(['telnyx_verify'])
    expect(events.map { |event| event.data['channel'] }.uniq).to eq(['sms'])
    expect(events.map { |event| event.data['telnyx_verification_id'] }.compact.uniq).to eq(['verification-1'])
    expect(events.map { |event| event.data['provider_status'] }.uniq).to eq(['accepted'])
    expect(events.map { |event| event.data['ip'] }.uniq).to eq(['203.0.113.10'])
    expect(events.map { |event| event.data['ua'] }.uniq).to eq(['Split portal test'])
    expect(submitter.reload.phone).to eq('(***) ***-1212')
  end

  it 'deduplicates a retried event by its external event id' do
    payload = {
      event_type: 'phone_verified',
      event_timestamp: '2026-07-29T12:00:00.000Z',
      data: {
        external_event_id: 'agreement_sms_phone_verified:document-128:verification-1',
        phone: '(***) ***-1212',
        provider: 'telnyx_verify',
        channel: 'sms'
      }
    }

    2.times do
      post "/api/submissions/#{submission.id}/audit_events", headers:, params: payload.to_json
      expect(response).to have_http_status(:ok)
    end

    expect(submission.reload.submission_events.where(event_type: 'phone_verified').count).to eq(1)
  end
end
