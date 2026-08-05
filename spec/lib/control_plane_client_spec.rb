# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ControlPlaneClient do
  describe '.upsert_merchant_document' do
    it 'updates the exact submission without reusing another agreement from the same template' do
      allow(described_class).to receive(:get).with(
        '/rest/v1/merchant_documents',
        hash_including(
          'merchant_id' => 'eq.merchant-1',
          'template_id' => 'eq.1',
          'submission_id' => 'eq.202'
        )
      ).and_return([{ 'id' => 'document-202' }])
      allow(described_class).to receive(:patch).and_return([{ 'id' => 'document-202' }])

      result = described_class.upsert_merchant_document(
        merchant_id: 'merchant-1', template_id: 1, submission_id: 202, status: 'signed'
      )

      expect(result.first['id']).to eq('document-202')
      expect(described_class).to have_received(:patch).with(
        '/rest/v1/merchant_documents',
        hash_including(submission_id: 202, status: 'signed'),
        { 'id' => 'eq.document-202' }
      )
    end

    it 'inserts a repeat agreement when no matching submission or unsigned placeholder exists' do
      allow(described_class).to receive(:get).and_return([], [])
      allow(described_class).to receive(:post).and_return([{ 'id' => 'new-document' }])

      described_class.upsert_merchant_document(
        merchant_id: 'merchant-1', template_id: 1, submission_id: 303, status: 'sent'
      )

      expect(described_class).to have_received(:post).with(
        '/rest/v1/merchant_documents',
        hash_including(merchant_id: 'merchant-1', template_id: 1, submission_id: 303)
      )
    end
  end

  describe '.find_merchant_for_document_context' do
    it 'fails closed when one email belongs to multiple portal merchants' do
      allow(described_class).to receive(:get).and_return([
        { 'id' => 'merchant-1' },
        { 'id' => 'merchant-2' }
      ])

      expect(described_class.find_merchant_for_document_context(email: 'shared@example.com')).to be_nil
    end
  end

  describe '.execute' do
    it 'normalizes upstream timeouts so portal submission creation can recover' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Net::ReadTimeout)

      expect do
        described_class.send(
          :execute,
          URI.parse('https://control.example.com/rest/v1/merchant_documents'),
          Net::HTTP::Get.new('/')
        )
      end.to raise_error(ControlPlaneClient::Error, 'Split control plane request failed: Net::ReadTimeout')
    end
  end
end
