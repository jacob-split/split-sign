# Pure policy regression: no Rails, database or outgoing messages.
require_relative '../app/services/merchant_portal_review_agreement_generator'
Submitter = Struct.new(:metadata)
%w[onyx_private_client default_payroc_tcg epi_cygma_advantage].each do |key|
  raise "extra generation enabled for #{key}" unless MerchantPortalReviewAgreementGenerator.exact_portal_packet_submitter?(Submitter.new({'agreement_stack_key'=>key}))
end
raise 'legacy compatibility changed' if MerchantPortalReviewAgreementGenerator.exact_portal_packet_submitter?(Submitter.new({}))
puts '4 package-selection policy checks passed'
