# Validates this reviewed packet before any merchant template or submission writes.
module FundingPacketLayout
  module_function
  def validate!(layout, fields, state)
    state=state.to_s.strip.upcase
    raise ArgumentError, 'Merchant state is required as a two-letter code to select funding disclosures' unless state.match?(/\A[A-Z]{2}\z/)
    disclosure_states=layout.fetch('disclosurePages').flat_map { |item| item.fetch('states') }
    if disclosure_states.include?(state)
      raise ArgumentError, "Funding packet disclosure mapping for #{state} requires review before generation"
    end
    names=fields.select { |field| field['type']=='signature' }.map { |field| field['name'] }
    expected=layout.fetch('fields').map { |field| field['name'] }
    raise ArgumentError, 'Funding master signature map has drifted' unless names.sort==expected.sort
    expected.size+1 # The separate Letter of Direction requires one merchant signature.
  end
end
