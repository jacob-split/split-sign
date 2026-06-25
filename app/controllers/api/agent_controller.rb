# frozen_string_literal: true

require 'split_agent_contract'

module Api
  class AgentController < ActionController::API
    def capabilities
      render json: SplitAgentContract.contract
    end

    def readiness
      render json: SplitAgentContract.readiness
    end

    def openapi
      render json: SplitAgentContract.openapi
    end

    def agent_json
      render json: SplitAgentContract.contract
    end

    def agent_card
      render json: SplitAgentContract.agent_card
    end

    def invoke
      action = SplitAgentContract.actions.find { |item| item[:id] == params[:action_id] }

      unless action
        return render json: { error: 'Unknown agent action', action_id: params[:action_id] }, status: :not_found
      end

      unless action[:callable]
        return render json: {
          error: 'Action is not callable through the public Split Signature agent surface.',
          action_id: params[:action_id],
          risk: action[:risk],
          proof: action[:proof]
        }, status: :forbidden
      end

      render json: { error: 'No callable actions are currently implemented.' }, status: :not_implemented
    end
  end
end
