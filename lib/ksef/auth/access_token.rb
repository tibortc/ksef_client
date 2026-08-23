# frozen_string_literal: true

module Ksef
  module Auth
    # Holds the redeemed token pair and keeps the access token fresh
    # (DESIGN.md §5.1, §6.3; docs/REFERENCE.md §4.2).
    #
    # ## Expiry comes from the response, never from the JWT
    #
    # The access token is a JWT, and it is tempting to read `exp` out of it. This gem does
    # not, and that is a locked decision: DESIGN.md §4.3 excludes the `jwt` dependency and
    # treats the token as an opaque bearer string, and the contract's `TokenInfo` carries
    # `validUntil` precisely so no decoding is needed. (§6.3 used to say "expiry in `exp`",
    # contradicting §4.3; corrected 2026-08-23.)
    #
    # ## Why refresh early rather than on expiry
    #
    # Refreshing at ~80% of the token's life means a request never carries a credential that
    # expires mid-flight. Waiting for expiry guarantees the opposite: the first request after
    # the deadline fails, and on a non-idempotent call — an invoice submission — a failure
    # that *might* have been delivered is exactly the situation this gem works hardest to
    # avoid (DESIGN.md §6.7).
    #
    # ## Thread safety
    #
    # A `Ksef::Client` is shareable across threads (DESIGN.md §5.2), so this is the piece
    # that has to be safe: one mutex guards the pair, and the staleness check is re-run
    # inside the lock so a burst of threads produces one refresh rather than a stampede.
    #
    # **Not in scope here:** the 401 refresh-and-replay of §6.3. That needs to see the
    # response, so it belongs to the HTTP layer; this class only refreshes on time.
    class AccessToken
      REDACTED = "[REDACTED]"

      # Fraction of the access token's observed lifetime after which it is considered stale.
      # "~80%" per §6.3 — the docs describe the lifetime only as "kilkanaście minut", so a
      # proportion travels better than a fixed number of seconds.
      REFRESH_THRESHOLD = 0.8

      # @param tokens [Tokens] the pair from `POST /auth/token/redeem`
      # @param client [Client] used for `POST /auth/token/refresh`
      # @param clock [#call] injected for tests; returns the current {Time}
      # @param threshold [Float] override for {REFRESH_THRESHOLD}
      def initialize(tokens, client:, clock: -> { Time.now }, threshold: REFRESH_THRESHOLD)
        @client = client
        @clock = clock
        @threshold = threshold
        @mutex = Mutex.new
        @access = tokens.access_token
        @refresh = tokens.refresh_token
        # The issue time is not in the response, so the lifetime is measured from when we
        # took delivery. That can only *under*-estimate the remaining life, which errs the
        # safe way: we refresh slightly early rather than slightly late.
        @acquired_at = @clock.call
      end

      # The bearer string for an `Authorization` header, refreshing first if the token has
      # gone stale.
      #
      # **This may perform a network call** — deliberately named `#bearer` rather than
      # `#token` so that is not a surprise at the call site.
      #
      # @return [String]
      # `@access.nil?` is not a paranoid guard: `TokenInfo.from(nil)` returns nil, so a
      # redeem response missing its `accessToken` produces a pair with no token at all.
      # Without this arm that state reaches `nil.token` and reports `NoMethodError` from
      # deep inside the client, instead of saying the credential is unusable.
      def bearer
        @mutex.synchronize do
          renew! if @access.nil? || stale_unlocked?
          @access.token
        end
      end

      # Forces a refresh regardless of staleness.
      #
      # @return [self]
      def refresh!
        @mutex.synchronize { renew! }
        self
      end

      # @return [Time, nil] when the current access token stops being valid
      def valid_until = @access&.valid_until

      def expired?(now = @clock.call) = @access.nil? || @access.expired?(now)

      # True once the token is past {REFRESH_THRESHOLD} of its observed lifetime.
      #
      # False when the lifetime cannot be established, which is the conservative answer: a
      # `validUntil` we could not parse is no reason to spend a refresh, and a genuinely
      # expired token still surfaces as a 401 from the API.
      def stale?(now = @clock.call)
        deadline = refresh_deadline
        !deadline.nil? && now >= deadline
      end

      # The refresh token is valid up to seven days and is reusable (§4.2). Once it lapses
      # there is no way back but a full re-authentication.
      def refresh_token_expired?(now = @clock.call) = @refresh.nil? || @refresh.expired?(now)

      # Both redacted, `#to_s` included: these are live credentials, and interpolating one
      # into a log line is how they escape (DESIGN.md §4.5).
      def to_s = REDACTED

      def inspect
        "#<Ksef::Auth::AccessToken token=#{REDACTED} valid_until=#{valid_until.inspect} " \
          "stale=#{stale?} refresh=#{REDACTED}>"
      end

      private

      # Callers hold the mutex, and it is the *caller* that decides whether a refresh is
      # wanted: {#bearer} asks only when stale, {#refresh!} always. Guarding staleness in
      # here as well would silently make `refresh!` conditional, which is not what it says.
      #
      # The stampede protection lives in {#bearer} instead, and works because the check
      # happens inside the lock: the first thread through refreshes, `@acquired_at` moves,
      # and every thread behind it sees a fresh token.
      def renew!
        if refresh_token_expired?
          raise AuthenticationError,
                "The refresh token expired at #{@refresh&.valid_until.inspect}, so the access token " \
                "cannot be renewed. Re-authenticate from the challenge (docs/REFERENCE.md §4.2)."
        end

        @access = @client.refresh(refresh_token: @refresh.token)
        @acquired_at = @clock.call
      end

      def stale_unlocked?
        deadline = refresh_deadline
        !deadline.nil? && @clock.call >= deadline
      end

      # `nil` when the lifetime is unknowable — no token, or no parsed `validUntil`.
      def refresh_deadline
        return nil if @access.nil?

        expiry = @access.valid_until
        return nil if expiry.nil?

        lifetime = expiry - @acquired_at
        return @acquired_at if lifetime <= 0

        @acquired_at + (lifetime * @threshold)
      end
    end
  end
end
