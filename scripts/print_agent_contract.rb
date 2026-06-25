# frozen_string_literal: true

require 'json'
require_relative '../lib/split_agent_contract'

target = ARGV.first || 'contract'
payload =
  case target
  when 'openapi'
    SplitAgentContract.openapi
  when 'readiness'
    SplitAgentContract.readiness
  else
    SplitAgentContract.contract
  end

puts JSON.pretty_generate(payload)
