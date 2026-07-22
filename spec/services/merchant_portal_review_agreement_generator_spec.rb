# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MerchantPortalReviewAgreementGenerator do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:, email: 'admin@split-llc.com') }
  let(:folder) { create(:template_folder, account:, author:, name: 'Portal Agreements') }
  let(:source_template) { create(:template, account:, author:, folder:, attachment_count: 0) }
  let(:source_submission) { create(:submission, :with_submitters, template: source_template, created_by_user: author) }
  let(:source_submitter) { source_submission.submitters.first }
  let(:merchant) do
    {
      'id' => 'merchant-abc',
      'business_name' => 'Beanfish LLC',
      'dba_name' => 'Beanfish',
      'business_email' => 'owner@example.com',
      'business_phone' => '3365550100',
      'street' => '1 Main St',
      'city' => 'Winston Salem',
      'state' => 'NC',
      'zip' => '27106',
      'monthly_volume' => 12_000
    }
  end
  let(:principal) do
    {
      'first_name' => 'Ada',
      'last_name' => 'Lovelace',
      'title' => 'Owner',
      'ownership_pct' => 100,
      'phone' => '3365550101'
    }
  end

  def create_master_template!(id, name)
    template = create(:template, id:, account:, author:, folder:, name:, attachment_count: 0)
    submitter_uuid = template.submitters.first['uuid']
    template.update!(
      fields: [
        {
          'uuid' => SecureRandom.uuid,
          'submitter_uuid' => submitter_uuid,
          'name' => 'Business Email',
          'type' => 'text',
          'required' => false,
          'preferences' => {},
          'areas' => []
        },
        {
          'uuid' => SecureRandom.uuid,
          'submitter_uuid' => submitter_uuid,
          'name' => 'Owner Full Name',
          'type' => 'text',
          'required' => false,
          'preferences' => {},
          'areas' => []
        },
        {
          'uuid' => SecureRandom.uuid,
          'submitter_uuid' => submitter_uuid,
          'name' => 'Signature',
          'type' => 'signature',
          'required' => true,
          'preferences' => {},
          'areas' => []
        }
      ],
      schema: []
    )
    template
  end

  before do
    create_master_template!(1, 'Merchant Processing & MLA Agreements')
    create_master_template!(95, 'FRPA_payroc')
    source_submitter.update!(metadata: { 'merchant_id' => 'merchant-abc', 'source' => described_class::PORTAL_ONBOARDING_SOURCE })

    allow(described_class).to receive(:configured_master_template_ids).and_return([1, 95])
    allow(SupabaseClient).to receive(:fetch_merchant).with('merchant-abc').and_return(merchant)
    allow(SupabaseClient).to receive(:fetch_principals).with('merchant-abc').and_return([principal])
    allow(SupabaseClient).to receive(:fetch_merchant_documents).with('merchant-abc').and_return([])
    allow(SupabaseClient).to receive(:fetch_template_field_mappings).and_return(nil)
    allow(SupabaseClient).to receive(:upsert_merchant_document) do |attrs|
      [{ 'id' => "doc-#{attrs[:template_id]}" }]
    end
    allow(SearchEntries).to receive(:enqueue_reindex) if defined?(SearchEntries)
  end

  it 'creates merchant-specific Portal Agreements clones, no-email submissions, and portal document rows' do
    result = described_class.call(merchant_id: 'merchant-abc', source_submitter:)

    expect(result[:errors]).to eq([])
    expect(result[:created_count]).to eq(2)

    clones = Template.where(external_id: [
      described_class.clone_external_id(1, 'merchant-abc'),
      described_class.clone_external_id(95, 'merchant-abc')
    ]).order(:id)
    expect(clones.size).to eq(2)
    expect(clones.map(&:name)).to all(include('beanfish_llc'))
    expect(clones.map { |clone| clone.folder.name }.uniq).to eq(['Portal Agreements'])
    expect(clones.map { |clone| clone.preferences['source'] }.uniq).to eq([described_class::GENERATED_SOURCE])
    expect(clones.flat_map(&:fields).select { |field| field['name'] == 'Business Email' }.map { |field| field['default_value'] }.uniq).to eq(['owner@example.com'])

    generated_submissions = Submission.where(template_id: clones.pluck(:id)).includes(:submitters)
    expect(generated_submissions.size).to eq(2)
    generated_submissions.each do |submission|
      submitter = submission.submitters.first
      expect(submitter.email).to eq('owner@example.com')
      expect(submitter.preferences['send_email']).to eq(false)
      expect(submitter.metadata['merchant_id']).to eq('merchant-abc')
      expect(submitter.metadata['source']).to eq(described_class::GENERATED_SOURCE)
    end

    expect(SupabaseClient).to have_received(:upsert_merchant_document).twice
    expect(SupabaseClient).to have_received(:upsert_merchant_document).with(hash_including(merchant_id: 'merchant-abc', status: 'pending')).twice
  end


  it 'rejects master templates outside Portal Agreements' do
    foreign_folder = create(:template_folder, account:, author:, name: 'Other')
    template = Template.find(1)
    template.update!(folder: foreign_folder)

    result = described_class.call(merchant_id: 'merchant-abc', source_submitter:)

    expect(result[:errors]).to include('Master review template 1 is outside Portal Agreements')
  end

  it 'is triggered only by portal onboarding submitters' do
    expect(described_class).to receive(:call).with(merchant_id: 'merchant-abc', source_submitter:)
    described_class.maybe_generate_for_portal_onboarding([source_submission])
  end
end
