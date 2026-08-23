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

        # A second connection for **pre-signed storage links**, which are not KSeF API
        # routes (docs/REFERENCE.md §14.2).
        #
        # Its whole purpose is what it leaves out. A `downloadUrl` is a pre-signed Azure
        # Blob URI carrying its own authorisation in the query string, and the contract says
        # outright not to send the access token to it — doing so would hand a live KSeF
        # credential to third-party storage. Keeping those requests on a connection that has
        # no bearer, and no `base_url` to accidentally resolve against, makes that structural
        # rather than a rule someone has to remember.
        #
        # Also omitted: JSON encoding and parsing, since a UPO is XML and must be kept as
        # the exact bytes received (§12 — it is XAdES-signed, and re-serialising it risks
        # invalidating the signature); and {SystemWarning}, whose header is an API concern.
        # Retained: TLS settings, timeouts, proxy and the error handler.
        #
        # @return [Faraday::Connection]
        def storage(config)
          Faraday.new(headers: { "User-Agent" => config.user_agent }) do |f|
            f.use ErrorHandler
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
            # Opts into RFC7807 error bodies. Every one of the 83 operations documents
            # this header, and the modern envelope is opt-in: without it the API returns
            # the deprecated shapes, which carry no traceId, no structured `errors[]`
            # codes on 400 and no reasonCode on 403 (docs/REFERENCE.md §5.1).
            "X-Error-Format" => "problem-details",
            "User-Agent" => config.user_agent
          }
        end
      end
    end
  end
end
