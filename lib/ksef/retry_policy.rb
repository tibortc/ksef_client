# frozen_string_literal: true

module Ksef
  # When the client may transparently retry a request.
  #
  # The governing rule from DESIGN.md §6.7 is a business one, not a technical one:
  # **invoice submission is never auto-retried.** A duplicate invoice in KSeF is a real
  # tax problem that the gem must not create on a user's behalf. So retries are gated on
  # the HTTP method being idempotent, not merely on the status looking transient — a 429
  # on a POST is surfaced as {Ksef::RateLimitedError} with `#retry_after` for the caller
  # to act on deliberately.
  RetryPolicy = Data.define(
    :max_attempts,
    :base_interval,
    :max_interval,
    :max_retry_after,
    :backoff_factor,
    :retry_statuses,
    :respect_retry_after
  )

  # Behaviour for {Ksef::RetryPolicy}.
  class RetryPolicy
    # Methods with no side effects, so replaying them is safe.
    IDEMPOTENT_METHODS = %i[get head].freeze

    class << self
      def default
        new(
          max_attempts: 3,
          base_interval: 1.0,
          max_interval: 30.0,
          max_retry_after: 60.0,
          backoff_factor: 2.0,
          retry_statuses: [429, 500, 502, 503, 504].freeze,
          respect_retry_after: true
        )
      end

      # Disable retries entirely.
      def none
        default.with(max_attempts: 1)
      end
    end

    # @param method [Symbol] the HTTP verb, lowercase
    # @param status [Integer, nil] the response status, or nil for a transport failure
    # @param attempt [Integer] 1-based
    # @param retry_after [Integer, Float, nil] seconds, from the `Retry-After` header
    def retryable?(method:, status:, attempt: 1, retry_after: nil)
      return false if attempt >= max_attempts
      return false unless IDEMPOTENT_METHODS.include?(method.to_s.downcase.to_sym)
      # Waiting less than the server demanded provokes a longer block, so if we are not
      # prepared to wait the full period we must not retry at all.
      return false if respect_retry_after && retry_after && retry_after.to_f > max_retry_after
      return true if status.nil? # connection reset / timeout on an idempotent request

      retry_statuses.include?(status)
    end

    # Seconds to wait before the next attempt.
    #
    # `Retry-After` wins over the computed backoff, and is deliberately **not** clamped to
    # `max_interval`: on 429 the block period is dynamic and lengthens with repeat
    # offences, so retrying earlier than the server asked makes things strictly worse
    # (docs/REFERENCE.md §6). `max_retry_after` bounds this instead, by declining the
    # retry outright in {#retryable?}.
    #
    # @param attempt [Integer] 1-based
    # @param retry_after [Integer, Float, nil] seconds, from the `Retry-After` header
    def interval_for(attempt:, retry_after: nil)
      return retry_after.to_f if respect_retry_after && retry_after

      [base_interval * (backoff_factor**(attempt - 1)), max_interval].min
    end
  end
end
