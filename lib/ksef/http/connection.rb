# frozen_string_literal: true

require "faraday"

module Ksef
  module HTTP
    # Builds the single Faraday connection a {Ksef::Client} owns.
    #
    # One connection per client, shared across threads — safe with the default `net_http`
    # adapter (DESIGN.md §5.2). The adapter is kept swappable via configuration.
    module Connection
      # `application/problem+json` is the current error content type, so the response
      # parser must match it as well as plain `application/json`
      # (docs/REFERENCE.md §5.1).
      JSON_CONTENT_TYPE = /\bjson\b/

      class << self
        # @param config [Ksef::Configuration]
        # @return [Faraday::Connection]
        def build(config)
          Faraday.new(url: config.base_url, headers: default_headers(config)) do |f|
            f.request :json

            # Registration order is load-bearing. Faraday runs `on_complete` callbacks
            # innermost-first, so the JSON parser must be registered *after* the error
            # handler for the handler to see a decoded body rather than a raw string.
            f.use ErrorHandler
            f.use SystemWarning, logger: config.logger
            f.response :json, content_type: JSON_CONTENT_TYPE

            apply_transport_options(f, config)
            f.adapter config.adapter
          end
        end

        private

        def apply_transport_options(faraday, config)
          faraday.options.open_timeout = config.open_timeout
          faraday.options.timeout = config.read_timeout
          faraday.proxy = config.proxy if config.proxy

          # TLS verification is never disabled, on any code path (DESIGN.md §4.5).
          faraday.ssl.verify = true
          faraday.ssl.min_version = :TLS1_2
        end

        def default_headers(config)
          {
            "Accept" => "application/json",
            "User-Agent" => config.user_agent
          }
        end
      end
    end
  end
end
