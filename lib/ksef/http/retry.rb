# frozen_string_literal: true

require "faraday"

module Ksef
  module HTTP
    # Re-issues a failed request when {Ksef::RetryPolicy} says it is safe to.
    #
    # Until 2026-08-23 this did not exist: `RetryPolicy` was constructed, validated,
    # documented as a constructor option and **never consulted**, so `Retry-After` was
    # honoured nowhere and `retry:` was silently inert. The policy object was right all
    # along; nothing called it.
    #
    # ## What may be retried, and why so little
    #
    # Every decision is delegated to {Ksef::RetryPolicy#retryable?}, which refuses anything
    # but `GET` and `HEAD` (DESIGN.md §6.7). That rule is a business one, not a technical
    # one: **a duplicate invoice in KSeF is a real tax problem**, so a POST whose response
    # never arrived must surface to the caller, who alone knows whether re-sending is safe.
    # The per-invoice duplicate status `440` exists precisely because this happens, and it
    # is not this middleware's job to make it happen more often.
    #
    # There is exactly one documented exception anywhere in the gem, and it is *not* here:
    # {Ksef::Crypto::PublicKeys#with_key_rotation}'s opt-in `21470` remediation, which a
    # caller invokes deliberately (docs/REFERENCE.md §10.2).
    #
    # ## Placement in the stack is load-bearing
    #
    # Registered **outside** {ErrorHandler}, so it catches the typed exceptions the handler
    # raises rather than inspecting raw statuses — one place decides what a status means.
    # Registered **inside** `request :json`, so a retry re-sends the already-encoded body
    # instead of encoding it twice.
    #
    # The body is restored before each attempt because an adapter may consume it: without
    # that, attempt two sends an empty body and the retry silently changes the request.
    class Retry < Faraday::Middleware
      # The four classes {ErrorHandler} raises that can be worth another attempt: a rate
      # limit, a server fault, and the two transport failures. Everything else — 400, 401,
      # 403, 410 — is a definite answer that retrying cannot improve.
      RETRYABLE = [
        Ksef::RateLimitedError,
        Ksef::ServerError,
        Ksef::TimeoutError,
        Ksef::ConnectionError
      ].freeze

      # @param policy [Ksef::RetryPolicy] anything answering `#retryable?` and `#interval_for`
      # @param sleeper [#call] injected for tests; receives seconds
      # @param logger [#info, nil] a retry is worth a line, since it hides latency
      def initialize(app, policy:, sleeper: nil, logger: nil)
        super(app)
        @policy = policy
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @logger = logger
      end

      def call(env)
        body = env.body
        attempt = 1

        begin
          env.body = body
          @app.call(env)
        rescue *RETRYABLE => e
          raise unless retry?(env, e, attempt)

          wait = @policy.interval_for(attempt: attempt, retry_after: retry_after(e))
          announce(env, e, attempt, wait)
          @sleeper.call(wait)
          attempt += 1
          retry
        end
      end

      private

      def retry?(env, error, attempt)
        @policy.retryable?(
          method: env.method,
          status: status_of(error),
          attempt: attempt,
          retry_after: retry_after(error)
        )
      end

      # `nil` for a transport failure, which the policy treats as retryable on an idempotent
      # request — there is no response to read a status from.
      def status_of(error) = error.respond_to?(:status) ? error.status : nil

      # Only a 429 carries one, and the policy honours it **unclamped**: waiting less than
      # the server asked for lengthens the block, and KSeF treats repeat offences as an
      # abuse pattern (docs/REFERENCE.md §6).
      def retry_after(error) = error.respond_to?(:retry_after) ? error.retry_after : nil

      def announce(env, error, attempt, wait)
        return if @logger.nil?

        @logger.info(
          "ksef_client: retrying #{env.method.to_s.upcase} #{env.url&.path} " \
          "after #{error.class.name.split("::").last} — attempt #{attempt + 1} in #{wait}s"
        )
      end
    end
  end
end
