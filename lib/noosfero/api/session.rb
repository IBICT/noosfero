require "uri"

module Noosfero
  module API

    class Session < Grape::API

      # Login to get token
      #
      # Parameters:
      #   login (*required) - user login or email
      #   password (required) - user password
      #
      # Example Request:
      #  POST http://localhost:3000/api/v1/login?login=adminuser&password=admin
      post "/login" do
        user ||= User.authenticate(params[:login], params[:password], environment)

        return unauthorized! unless user
        user.generate_private_token!
        @current_user = user
        present user, :with => Entities::UserLogin
      end

      # Create user.
      #
      # Parameters:
      #   email (required)                  - Email
      #   password (required)               - Password
      #   login                             - login
      # Example Request:
      #   POST /register?email=some@mail.com&password=pas&login=some
      params do
        requires :email, type: String, desc: _("Email")
        requires :login, type: String, desc: _("Login")
        requires :password, type: String, desc: _("Password")
      end
      post "/register" do
        binding.pry
        unique_attributes! User, [:email, :login]
        attrs = attributes_for_keys [:email, :login, :password] + environment.signup_person_fields
        attrs[:password_confirmation] = attrs[:password]

        remote_ip = (request.respond_to?(:remote_ip) && request.remote_ip) || (env && env['REMOTE_ADDR'])
        private_key = API.NOOSFERO_CONF['api_recaptcha_private_key']
        api_recaptcha_verify_uri = API.NOOSFERO_CONF['api_recaptcha_verify_uri']

#        "recaptcha_challenge_field" => "03AHJ_VutRW6eOgTKZyK-77J96k121W0fUHIEvThyCPtqG2FUPBWzidBOqptzk0poh_UkMNPxAd_m0CqUz1Dip-6uV_zlwlviaXXvymwCFXPaWuvvyUfZ3LvZy6M1CoPfbhOQZjTkf_VNjlVnCRuuJXmGy4MhhuJ8om1J_R2C_oIAfP3KbpmlqLXU5nLlE7WpW-h-OhRTQzupTo9UL-4-ZDRk1bMkCSEJnwYUomOboqFBEpJBv0iaOCaSnu9_UKObmWmpbQZSHxYK7",
#            "recaptcha_response_field" => "1221"

        #captcha_result = verify_recaptcha_v2(remote_ip, params['g-recaptcha-response'], private_key, api_recaptcha_verify_uri)
        captcha_result = verify_recaptcha_v1(remote_ip, params['recaptcha_response_field'], private_key, params['recaptcha_challenge_field'], api_recaptcha_verify_uri)
        binding.pry
        user = User.new(attrs)  
        if captcha_result["success"] and user.save
          user.activate
          user.generate_private_token!
          present user, :with => Entities::UserLogin
        else
          message = user.errors.to_json
          render_api_error!(message, 400)
        end
      end
    end
  end
end
