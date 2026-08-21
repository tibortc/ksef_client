# frozen_string_literal: true

require "faraday"

module Ksef
  module HTTP
    # Maps KSeF error responses and Faraday transport failures onto the {Ksef::Error}
    # hierarchy (DESIGN.md §6.7).
    #
    # Status coverage follows what the contract actually declares — 400, 401, 403, 410
    # and 429 (docs/REFERENCE.md §5.4). 5xx is handled defensively: the spec never
    # declares it, so the body shape is unknown and degrades to a raw payload.
    class ErrorHandler < Faraday::Middleware
      STATUS_MAP = {
        400 => ApiError,
        401 => AuthenticationError,
        403 => AuthorizationError,
        410 => ResourceGoneError,
        429 => RateLimitedError
      }.freeze

      def call(env)
        super
      rescue Faraday::TimeoutError => e
        raise Ksef::TimeoutError, "KSeF request timed out: #{e.message}"
      rescue Faraday::SSLError => e
        raise Ksef::ConnectionError, "TLS failure talking to KSeF: #{e.message}"
      rescue Faraday::ConnectionFailed => e
        # The net_http adapter reports `Net::OpenTimeout` as a connection failure, which
        # loses the distinction a caller most needs after submitting an invoice: a
        # timeout may have been processed server-side, a refused connection was not.
        raise Ksef::TimeoutError, "KSeF connection timed out: #{e.message}" if timeout?(e.wrapped_exception)

        raise Ksef::ConnectionError, "Could not connect to KSeF: #{e.message}"
      end

      def on_complete(env)
        status = env.status
        return if status < 400

        problem = ProblemDetails.parse(status: status, body: env.body)
        raise build_error(status, problem, env)
      end

      private

      # `Net::OpenTimeout` and `Net::ReadTimeout` both descend from `Timeout::Error`.
      def timeout?(wrapped)
        defined?(Timeout::Error) && wrapped.is_a?(Timeout::Error)
      end

      def build_error(status, problem, env)
        message = "KSeF API #{status}: #{problem.summary}"
        message = "#{message} (traceId: #{problem.trace_id})" if problem.trace_id

        if status == 429
          RateLimitedError.new(message, problem: problem, retry_after: retry_after_from(env))
        else
          error_class(status).new(message, problem: problem)
        end
      end

      def error_class(status)
        STATUS_MAP[status] || (status >= 500 ? ServerError : ApiError)
      end

      # `Retry-After` is present on every declared 429 and is expressed in seconds
      # (docs/REFERENCE.md §5.5). The HTTP-date form is accepted defensively.
      def retry_after_from(env)
        raw = env.response_headers&.[]("Retry-After")
        return if raw.nil? || raw.to_s.strip.empty?

        value = raw.to_s.strip
        return Integer(value, 10) if /\A\d+\z/.match?(value)

        seconds = (Time.httpdate(value) - Time.now).ceil
        seconds.positive? ? seconds : 0
      rescue ArgumentError
        nil
      end
    end
  end
end
