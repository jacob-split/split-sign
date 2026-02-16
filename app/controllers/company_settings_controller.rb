# frozen_string_literal: true

class CompanySettingsController < ApplicationController
  before_action :authenticate_user!

  before_action do
    authorize!(:manage, EncryptedConfig)
  end

  def show
    @company_info = load_company_info
    @principals = load_principals
  end

  def update
    if params[:company_info].present?
      info_config = current_account.encrypted_configs
                                   .find_or_initialize_by(key: EncryptedConfig::COMPANY_INFO_KEY)
      info_config.value = params[:company_info].to_unsafe_h
      info_config.save!
    end

    if params[:principals].present?
      principals = params[:principals].to_unsafe_h.values.map do |p|
        p['ownership_pct'] = p['ownership_pct'].to_i if p['ownership_pct'].present?
        p.to_h
      end

      principals_config = current_account.encrypted_configs
                                         .find_or_initialize_by(key: EncryptedConfig::COMPANY_PRINCIPALS_KEY)
      principals_config.value = principals
      principals_config.save!
    end

    redirect_to settings_company_path, notice: 'Company information saved'
  end

  private

  def load_company_info
    current_account.encrypted_configs
                   .find_by(key: EncryptedConfig::COMPANY_INFO_KEY)&.value || {}
  end

  def load_principals
    current_account.encrypted_configs
                   .find_by(key: EncryptedConfig::COMPANY_PRINCIPALS_KEY)&.value || []
  end
end
