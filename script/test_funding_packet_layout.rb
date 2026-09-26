require 'json'
require_relative '../lib/funding_packet_layout'
layout=JSON.parse(File.read(File.join(__dir__,'funding_signature_layout.json')))
fields=layout['fields'].map{|f|{'type'=>'signature','name'=>f['name']}}
raise 'Core and LOD signature count mismatch' unless FundingPacketLayout.validate!(layout,fields,'NC')==10
raise 'Whitespace normalization failed' unless FundingPacketLayout.validate!(layout,fields,' nc ')==10
['', 'North Carolina', 'FL','UT','CA','NY','VA','CT'].each do |state|
 rejected=false
 begin;FundingPacketLayout.validate!(layout,fields,state);rescue ArgumentError;rejected=true;end
 raise "Incomplete state packet accepted: #{state}" unless rejected
end
[fields[1..],fields+[fields.first],fields.map.with_index{|f,i|i==0 ? f.merge('type'=>'initials'):f}].each do |drifted|
 rejected=false
 begin;FundingPacketLayout.validate!(layout,drifted,'NC');rescue ArgumentError;rejected=true;end
 raise 'Signature contract drift accepted' unless rejected
end
puts 'Funding preflight: 13 assertions passed'
