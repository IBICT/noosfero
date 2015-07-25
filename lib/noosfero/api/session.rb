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
      #   POST /register?email=some@mail.com&password=pas&password_confirmation=pas&login=some
      params do
        requires :email, type: String, desc: _("Email")
        requires :login, type: String, desc: _("Login")
        requires :password, type: String, desc: _("Password")
        requires :password_confirmation, type: String, desc: _("Password confirmation")
      end
      post "/register" do
        unique_attributes! User, [:email, :login]
        attrs = attributes_for_keys [:email, :login, :password, :password_confirmation] + environment.signup_person_fields
        remote_ip = (request.respond_to?(:remote_ip) && request.remote_ip) || (env && env['REMOTE_ADDR'])
        # test_captcha will render_api_error! and exit in case of some problem
        # this return is only improve the clarity of the execution path
        return unless test_captcha(remote_ip, params, environment)
        user = User.new(attrs)
        if user.save
          user.generate_private_token! if user.activated?
          present user, :with => Entities::UserLogin
        else
          message = user.errors.to_json
          render_api_error!(message, 400)
        end
      end

      params do
        requires :activation_code, type: String, desc: _("Activation token")
      end

      # Activate a user.
      #
      # Parameter:
      #   activation_code (required)                  - Activation token
      # Example Request:
      #   PATCH /activate?activation_code=28259abd12cc6a64ef9399cf3286cb998b96aeaf
      patch "/activate" do
        user = User.find_by_activation_code(params[:activation_code])
        if user
          unless user.environment.enabled?('admin_must_approve_new_users')
            if user.activate
                user.generate_private_token!
                present user, :with => Entities::UserLogin
            end
          else
            if user.create_moderate_task
              user.activation_code = nil
              user.save!

              # Waiting for admin moderate user registration
              status 202
              body({
                :message => 'Waiting for admin moderate user registration'
              })
            end
          end
        else
          # Token not found in database
          render_api_error!(_('Token is invalid'), 412)
        end
      end

      # Request a new password.
      #
      # Parameters:
      #   value (required)                  - Email or login
      # Example Request:
      #   POST /forgot_password?value=some@mail.com
      post "/forgot_password" do
        requestors = fetch_requestors(params[:value])
        not_found! if requestors.blank?

        requestors.each do |requestor|
          ChangePassword.create!(:requestor => requestor)
        end
      end

      params do
        requires :code, type: String, desc: _("Forgot password code")
      end
      # Change password
      #
      # Parameters:
      #   code (required)                  - Change password code
      #   password (required)
      #   password_confirmation (required)
      # Example Request:
      #   PATCH /new_password?code=xxxx&password=secret&password_confirmation=secret
      patch "/new_password" do
        change_password = ChangePassword.find_by_code(params[:code])
        not_found! if change_password.nil?

        if change_password.update_attributes(:password => params[:password], :password_confirmation => params[:password_confirmation])
          change_password.finish
          present change_password.requestor.user, :with => Entities::UserLogin
        else
          something_wrong!
        end
      end

    end
  end
end
