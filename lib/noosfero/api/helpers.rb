  module Noosfero
    module API
      module APIHelpers
      PRIVATE_TOKEN_PARAM = :private_token
      DEFAULT_ALLOWED_PARAMETERS = [:parent_id, :from, :until, :content_type]

      include SanitizeParams

      def current_user
        private_token = (params[PRIVATE_TOKEN_PARAM] || headers['Private-Token']).to_s
        @current_user ||= User.find_by_private_token(private_token)
        @current_user = nil if !@current_user.nil? && @current_user.private_token_expired?
        @current_user
      end

      def current_person
        current_user.person unless current_user.nil?
      end

      def logout
        @current_user = nil
      end

      def environment
        @environment
      end

      def limit
        limit = params[:limit].to_i
        limit = default_limit if limit <= 0
        limit
      end

      def period(from_date, until_date)
        return nil if from_date.nil? && until_date.nil?

        begin_period = from_date.nil? ? Time.at(0).to_datetime : from_date
        end_period = until_date.nil? ? DateTime.now : until_date

        begin_period..end_period
      end

      def parse_content_type(content_type)
        return nil if content_type.blank?
        content_type.split(',').map do |content_type|
          content_type.camelcase
        end
      end

      ARTICLE_TYPES = Article.descendants.map{|a| a.to_s}

      def find_article(articles, id)
        article = articles.find(id)
        #article.display_to?(current_user.person) ? article : forbidden!
      end

      def post_article(asset, params)
        return forbidden! unless current_person.can_post_content?(asset)

        klass_type= params[:content_type].nil? ? 'TinyMceArticle' : params[:content_type]
        return forbidden! unless ARTICLE_TYPES.include?(klass_type)

        article = klass_type.constantize.new(params[:article])
        article.last_changed_by = current_person
        article.created_by= current_person
        article.profile = asset

        if !article.save
          render_api_errors!(article.errors.full_messages)
        end
        present article, :with => Entities::Article, :fields => params[:fields]
      end

      def present_article(asset)
        article = find_article(asset.articles, params[:id])
        present article, :with => Entities::Article, :fields => params[:fields]
      end

      def present_articles(asset)
        articles = select_filtered_collection_of(asset, 'articles', params)
        articles = articles.display_filter(current_person, nil)
        present articles, :with => Entities::Article, :fields => params[:fields]
      end

      def find_task(tasks, id)
        task = tasks.find(id)
        task.display_to?(current_user.person) ? task : forbidden!
      end

      def make_conditions_with_parameter(params = {})
        parsed_params = parser_params(params)
        conditions = {}
        from_date = DateTime.parse(parsed_params.delete(:from)) if parsed_params[:from]
        until_date = DateTime.parse(parsed_params.delete(:until)) if parsed_params[:until]

        conditions[:type] = parse_content_type(parsed_params.delete(:content_type)) unless parsed_params[:content_type].nil?

        conditions[:created_at] = period(from_date, until_date) if from_date || until_date
        conditions.merge!(parsed_params)

        conditions
      end

      def make_order_with_parameters(params)
        params[:order] || "created_at DESC"
      end

      def by_reference(scope, params)
        if params[:reference_id]
          created_at = scope.find(params[:reference_id]).created_at
          scope.send("#{params.key?(:oldest) ? 'older_than' : 'younger_than'}", created_at)
        else
          scope
        end
      end

      def select_filtered_collection_of(object, method, params)
        conditions = make_conditions_with_parameter(params)
        order = make_order_with_parameters(params)

        objects = object.send(method)
        objects = by_reference(objects, params)
        objects = objects.where(conditions).limit(limit).order(order)

        objects
      end

      def authenticate!
        unauthorized! unless current_user
      end

      # Checks the occurrences of uniqueness of attributes, each attribute must be present in the params hash
      # or a Bad Request error is invoked.
      #
      # Parameters:
      #   keys (unique) - A hash consisting of keys that must be unique
      def unique_attributes!(obj, keys)
        keys.each do |key|
          cant_be_saved_request!(key) if obj.send("find_by_#{key.to_s}", params[key])
        end
      end

      def attributes_for_keys(keys)
        attrs = {}
        keys.each do |key|
          attrs[key] = params[key] if params[key].present? or (params.has_key?(key) and params[key] == false)
        end
        attrs
      end

      def verify_recaptcha_v2(remote_ip, g_recaptcha_response, private_key, api_recaptcha_verify_uri)
        verify_hash = {
          "secret"    => private_key,
          "remoteip"  => remote_ip,
          "response"  => g_recaptcha_response
        }
        uri = URI(api_recaptcha_verify_uri)
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        request = Net::HTTP::Post.new(uri.path)
        request.set_form_data(verify_hash)
        JSON.parse(https.request(request).body)
      end

      ##########################################
      #              error helpers             #
      ##########################################

      def not_found!
        render_api_error!('404 Not found', 404)
      end

      def forbidden!
        render_api_error!('403 Forbidden', 403)
      end

      def cant_be_saved_request!(attribute)
        message = _("(Invalid request) #{attribute} can't be saved")
        render_api_error!(message, 400)
      end

      def bad_request!(attribute)
        message = _("(Bad request) #{attribute} not given")
        render_api_error!(message, 400)
      end

      def something_wrong!
        message = _("Something wrong happened")
        render_api_error!(message, 400)
      end

      def unauthorized!
        render_api_error!(_('Unauthorized'), 401)
      end

      def not_allowed!
        render_api_error!(_('Method Not Allowed'), 405)
      end

      def render_api_error!(message, status)
        error!({'message' => message, :code => status}, status)
      end

      def render_api_errors!(messages)
        render_api_error!(messages.join(','), 400)
      end
      protected

      def set_session_cookie
        cookies['_noosfero_api_session'] = { value: @current_user.private_token, httponly: true } if @current_user.present?
      end

      def setup_multitenancy
        Noosfero::MultiTenancy.setup!(request.host)
      end

      def detect_stuff_by_domain
        @domain = Domain.find_by_name(request.host)
        if @domain.nil?
          @environment = Environment.default
          if @environment.nil? && Rails.env.development?
            # This should only happen in development ...
            @environment = Environment.create!(:name => "Noosfero", :is_default => true)
          end
        else
          @environment = @domain.environment
        end
      end

      def filter_disabled_plugins_endpoints
        not_found! if Noosfero::API::API.endpoint_unavailable?(self, @environment)
      end

      private

      def parser_params(params)
        parsed_params = {}
        params.map do |k,v|
          parsed_params[k.to_sym] = v if DEFAULT_ALLOWED_PARAMETERS.include?(k.to_sym)
        end
        parsed_params
      end

      def default_limit
        20
      end

      def parse_content_type(content_type)
        return nil if content_type.blank?
        content_type.split(',').map do |content_type|
          content_type.camelcase
        end
      end

      def period(from_date, until_date)
        begin_period = from_date.nil? ? Time.at(0).to_datetime : from_date
        end_period = until_date.nil? ? DateTime.now : until_date
        begin_period..end_period
      end

      ##########################################
      #              captcha_helpers           #
      ##########################################

      def test_captcha(remote_ip, params, _environment = nil)
        environment ||= _environment
        d = environment.api_captcha_settings
        return true unless d[:enabled] == true

        if d[:provider] == 'google'
          raise ArgumentError, "Environment api_captcha_settings private_key not defined" if d[:private_key].nil?
          raise ArgumentError, "Environment api_captcha_settings version not defined" unless d[:version] == 1 || d[:version] == 2
          if d[:version]  == 1
            d[:verify_uri] ||= 'https://www.google.com/recaptcha/api/verify'
            return verify_recaptcha_v1(remote_ip, d[:private_key], d[:verify_uri], params[:recaptcha_challenge_field], params[:recaptcha_response_field])
          end
          if d[:version] == 2
            d[:verify_uri] ||= 'https://www.google.com/recaptcha/api/siteverify'
            return verify_recaptcha_v2(remote_ip, d[:private_key], d[:verify_uri], params[:g_recaptcha_response])
          end
        end
        if d[:provider] == 'serpro'
          d[:verify_uri] ||= 'http://captcha2.servicoscorporativos.serpro.gov.br/captchavalidar/1.0.0/validar'
          return verify_serpro_captcha(d[:serpro_client_id], params[:txtToken_captcha_serpro_gov_br], params[:captcha_text], d[:verify_uri])
        end
        raise ArgumentError, "Environment api_captcha_settings provider not defined"
      end

      def verify_recaptcha_v1(remote_ip, private_key, api_recaptcha_verify_uri, recaptcha_challenge_field, recaptcha_response_field)
        if recaptcha_challenge_field == nil || recaptcha_response_field == nil
          return _('Missing captcha data')
        end

        verify_hash = {
            "privatekey"  => private_key,
            "remoteip"    => remote_ip,
            "challenge"   => recaptcha_challenge_field,
            "response"    => recaptcha_response_field
        }
        uri = URI(api_recaptcha_verify_uri)
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        request = Net::HTTP::Post.new(uri.path)
        request.set_form_data(verify_hash)
        body = https.request(request).body
        body == "true\nsuccess" ? true : body
      end

      def verify_recaptcha_v2(remote_ip, private_key, api_recaptcha_verify_uri, g_recaptcha_response)
        if g_recaptcha_response == nil
          return _('Missing captcha data')
        end

        verify_hash = {
            "secret"    => private_key,
            "remoteip"  => remote_ip,
            "response"  => g_recaptcha_response
        }
        uri = URI(api_recaptcha_verify_uri)
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        request = Net::HTTP::Post.new(uri.path)
        request.set_form_data(verify_hash)
        captcha_result = JSON.parse(https.request(request).body)
        captcha_result["success"] ? true : captcha_result
      end

      def verify_serpro_captcha(client_id, token, captcha_text, verify_uri)
        if token == nil || captcha_text == nil
          return _('Missing captcha data')
        end
        uri = URI(verify_uri)
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path)
        verify_string = "#{client_id}&#{token}&#{captcha_text}"
        request.body = verify_string
        body = http.request(request).body
        body == '1' ? true : body 
      end

    end
  end
end
