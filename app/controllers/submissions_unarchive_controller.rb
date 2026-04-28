# frozen_string_literal: true

class SubmissionsUnarchiveController < ApplicationController
  load_and_authorize_resource :submission

  def create
    @submission.update!(archived_at: nil)
    MerchantPortalDocumentSync.sync_submissions([@submission], template: @submission.template)

    redirect_to submission_path(@submission), notice: I18n.t('submission_has_been_unarchived')
  end
end
