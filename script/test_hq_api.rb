# frozen_string_literal: true
require 'json'
require_relative '../lib/split_agent_contract'
doc = SplitAgentContract.openapi
operations = doc.fetch('paths').flat_map { |path, item| item.filter_map { |method, op| [path, method, op] if %w[get post put patch delete].include?(method) } }
native = operations.select { |path, _, _| !path.start_with?('/api/agent/') }
raise 'Missing native API routes' unless native.length == 36
raise 'Wrong prefix' unless native.all? { |path, _, _| path.start_with?('/api/') }
raise 'Duplicate operation IDs' unless native.map { |_, _, op| op['operationId'] }.uniq.length == 36
raise 'SDK discovery missing' unless SplitAgentContract.contract[:sdk][:namespace] == 'sign'
raise 'Public legacy writes enabled' if SplitAgentContract.actions.any? { |action| action[:callable] }
raise 'Submission name contract' unless doc.dig('paths', '/api/submissions', 'get', 'responses', '200', 'content', 'application/json', 'schema', 'properties', 'data', 'items', 'properties', 'name', 'nullable')
raise 'Optional metadata incorrectly required' if doc.dig('paths', '/api/submissions/{id}', 'get', 'responses', '200', 'content', 'application/json', 'schema', 'required').include?('metadata')
puts JSON.generate(passed: true, native_operations: native.length, public_legacy_mutations: false)
