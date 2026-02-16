# frozen_string_literal: true

class ApiDocsController < ActionController::Base
  def show
    render layout: false
  end

  def openapi
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = '*'

    send_file Rails.public_path.join('openapi.json'),
              type: 'application/json',
              disposition: 'inline'
  end
end
