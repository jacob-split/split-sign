# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Submitters::FormConfigs do
  describe '.typed_only_portal_fields' do
    let(:fields) do
      [
        { 'name' => 'Owner signature', 'type' => 'signature', 'preferences' => { 'format' => 'drawn_or_typed' } },
        { 'name' => 'Merchant initials', 'type' => 'initials', 'preferences' => {} },
        { 'name' => 'Printed name', 'type' => 'text', 'preferences' => {} }
      ]
    end

    it 'forces portal signatures and initials to typed format without mutating template fields' do
      result = described_class.typed_only_portal_fields(fields, portal_signing_flow: true)

      expect(result.first.dig('preferences', 'format')).to eq('typed')
      expect(result.second.dig('preferences', 'format')).to eq('typed')
      expect(result.third.dig('preferences', 'format')).to be_nil
      expect(fields.first.dig('preferences', 'format')).to eq('drawn_or_typed')
    end

    it 'preserves non-portal form behavior' do
      result = described_class.typed_only_portal_fields(fields, portal_signing_flow: false)

      expect(result).to equal(fields)
    end
  end
end
