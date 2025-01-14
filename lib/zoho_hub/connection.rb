# frozen_string_literal: true

require 'faraday'
require 'faraday_middleware'
require 'rainbow'
require 'addressable'

require 'zoho_hub/response'

module ZohoHub
  class Connection
    attr_accessor :debug, :access_token, :expires_in, :api_domain, :refresh_token

    # This is a block to be run when the token is refreshed. This way you can do whatever you want
    # with the new parameters returned by the refresh method.
    attr_accessor :on_refresh_cb

    DEFAULT_DOMAIN = 'https://www.zohoapis.com'

    BASE_PATH = '/crm/v2/'

    def initialize(access_token:, api_domain: DEFAULT_DOMAIN, expires_in: 3600, refresh_token: nil)
      @access_token = access_token
      @expires_in = expires_in
      @api_domain = api_domain
      @refresh_token ||= refresh_token # do not overwrite if it's already set
    end

    def get(path, params = {})
      log "GET #{path} with #{params}"

      response = with_refresh { adapter.get(path, params) }
      response.body
    end

    def post(path, params = {})
      log "POST #{path} with #{params}"

      response = with_refresh { adapter.post(path, params) }
      response.body
    end

    def put(path, params = {})
      log "PUT #{path} with #{params}"

      response = with_refresh { adapter.put(path, params) }
      response.body
    end

    def access_token?
      @access_token
    end

    def refresh_token?
      @refresh_token
    end

    def log(text)
      return unless self.debug

      puts Rainbow("[ZohoHub] #{text}").magenta.bright
    end

    private

    def with_refresh
      http_response = yield

      response = Response.new(http_response.body)

      # Try to refresh the token and try again
      if response.invalid_token? && refresh_token?
        log "Refreshing outdated token... #{@access_token}"
        params = ZohoHub::Auth.refresh_token(@refresh_token,  api_endpoint: api_domain)

        @on_refresh_cb.call(params) if @on_refresh_cb

        @access_token = params[:access_token]

        http_response = yield
      elsif response.authentication_failure?
        raise ZohoAPIError, response.msg
      end

      http_response
    end

    def base_url
      Addressable::URI.join(@api_domain, BASE_PATH).to_s
    end

    # The authorization header that must be added to every request for authorized requests.
    def authorization_header
      { 'Authorization' => "Zoho-oauthtoken #{@access_token}" }
    end

    def adapter
      Faraday.new(url: base_url) do |conn|
        conn.headers = authorization_header if access_token?
        conn.use FaradayMiddleware::ParseJson
        conn.response :json, parser_options: { symbolize_names: true }
        conn.response :logger if ZohoHub.configuration.debug?
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
