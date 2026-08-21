# frozen_string_literal: true

require "faraday"

module Ksef
  module HTTP
    # Surfaces the `X-System-Warning` header the API sets on every successful response
    # (docs/REFERENCE.md §5.5).
    #
    # This is the Ministry's in-band channel for advisory notices — deprecations,
    # forthcoming contract changes — and is not mentioned in DESIGN.md. Swallowing it
    # would mean users only learn about a change when it breaks them.
    class SystemWarning < Faraday::Middleware
      HEADER = "X-System-Warning"

      def initialize(app, logger: nil)
        super(app)
        @logger = logger
      end

      def on_complete(env)
        warning = env.response_headers&.[](HEADER)
        return if warning.nil? || warning.to_s.strip.empty?

        @logger&.warn("[ksef_client] #{HEADER}: #{warning}")
      end
    end
  end
end
