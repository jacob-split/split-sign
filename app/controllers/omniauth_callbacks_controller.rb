# frozen_string_literal: true

class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    auth = request.env['omniauth.auth']
    email = auth.info.email.to_s.downcase

    unless email.end_with?('@split-llc.com')
      flash[:alert] = 'Only @split-llc.com accounts are allowed.'
      return redirect_to new_user_session_path
    end

    user = User.active.find_by(email:)

    unless user
      flash[:alert] = 'No account found for this email. Contact your administrator.'
      return redirect_to new_user_session_path
    end

    sign_in_and_redirect user, event: :authentication
  end

  def failure
    flash[:alert] = 'Google authentication failed. Please try again.'
    redirect_to new_user_session_path
  end
end
