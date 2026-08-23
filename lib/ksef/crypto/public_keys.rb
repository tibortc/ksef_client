# frozen_string_literal: true

module Ksef
  module Crypto
    # The Ministry's published encryption certificates, fetched and cached
    # (docs/REFERENCE.md §10.2).
    #
    # `GET /security/public-key-certificates` is **unauthenticated** — the contract
    # declares no `security` for it — so this needs no credential and can run before any
    # authentication.
    #
    # ## Why there is a TTL, and why it is not "forever"
    #
    # Two rotation modes exist and must not be conflated. *Re-certification* issues a new
    # certificate over the same key pair, leaving `publicKeyId` unchanged. *Key rotation*
    # changes the key pair, so `publicKeyId` changes with it; a planned rotation publishes
    # the successor early and both appear for one `usage` during the overlap, while an
    # **emergency rotation revokes the old key and drops it from the list immediately**.
    # Because the emergency case can happen at any moment, the list must not be cached
    # indefinitely — and {#with_key_rotation} implements the documented recovery for the
    # window between a rotation and the cache expiring.
    #
    # Thread-safe: one mutex guards the cache, and a `Ksef::Client` is required to be
    # shareable across threads (DESIGN.md §5.2).
    class PublicKeys
      PATH = "security/public-key-certificates"

      # An hour. Long enough that the list is fetched once per process in practice, short
      # enough to bound how long a withdrawn key can linger. Callers who want none of it
      # can pass `ttl: 0`.
      DEFAULT_TTL = 3600

      # `400` with this code means "the supplied key identifier is unknown or refers to a
      # withdrawn key". The documented response is to re-fetch, re-select and repeat —
      # see {#with_key_rotation}.
      UNKNOWN_KEY_CODE = 21_470

      # @param connection [Faraday::Connection] usually from {Ksef::HTTP::Connection.build}
      # @param ttl [Numeric] seconds to cache the list for
      # @param clock [#call] injected for tests; returns the current {Time}
      def initialize(connection, ttl: DEFAULT_TTL, clock: -> { Time.now })
        @connection = connection
        @ttl = ttl
        @clock = clock
        @mutex = Mutex.new
        @certificates = nil
        @fetched_at = nil
      end

      # @return [Array<Certificate>] the cached list, fetching it if stale
      def all
        @mutex.synchronize { cached || load! }
      end

      # Discards the cache and fetches again. The recovery path of §10.2 after a key
      # rotation, and the only way to see a newly published certificate before the TTL
      # lapses.
      #
      # @return [Array<Certificate>]
      def refresh!
        @mutex.synchronize { load! }
      end

      # Applies the documented selection rule: filter by `usage`, require validity **at
      # the moment of use**, and where several qualify prefer the latest `validFrom`.
      #
      # Not a judgement call — §10.2 states it, which matters because during a planned
      # rotation overlap two certificates are legitimately valid for the same usage and
      # picking the older one wastes the overlap the Ministry provided.
      #
      # @param kind [String] one of {Certificate::USAGES}
      # @param at [Time, nil] the moment the key will be used; defaults to now
      # @return [Certificate]
      # @raise [Ksef::CryptoError] on an unknown usage, or when nothing published is valid
      def for_usage(kind, at: nil)
        validate_usage!(kind)
        moment = at || now
        usable = all.select { |certificate| certificate.usable_for?(kind) && certificate.valid_at?(moment) }
        usable.max_by(&:valid_from) || raise(CryptoError, nothing_valid(kind, moment))
      end

      # The key that wraps the KSeF token during authentication (§4.5).
      def token_encryption(at: nil) = for_usage(Certificate::KSEF_TOKEN_ENCRYPTION, at: at)

      # The key that wraps a session's AES key (§10.1).
      def symmetric_key_encryption(at: nil) = for_usage(Certificate::SYMMETRIC_KEY_ENCRYPTION, at: at)

      # Runs an operation, and on the one error that says "your key is stale" re-fetches
      # the list and runs it again.
      #
      # **This does not contradict the never-auto-retry-a-POST rule** (DESIGN.md §6.7). A
      # `21470` is the API declining the request outright, so nothing happened server-side
      # and there is no duplicate to create; and this is remediation — the second attempt
      # carries a *different* key identifier — rather than a blind replay. §10.2 prescribes
      # exactly this sequence.
      #
      # The block must therefore re-select the certificate itself, so pass the whole
      # operation rather than a pre-built request:
      #
      #     keys.with_key_rotation do
      #       session.open(encryption: encryptor.encryption_info(keys.symmetric_key_encryption))
      #     end
      #
      # @return the block's value
      def with_key_rotation
        yield
      rescue ApiError => e
        raise unless e.code == UNKNOWN_KEY_CODE

        refresh!
        yield
      end

      private

      def now = @clock.call

      # A typo would otherwise read as "the Ministry publishes no such key", sending the
      # reader to look for a rotation that never happened.
      def validate_usage!(kind)
        return if Certificate::USAGES.include?(kind)

        raise CryptoError, "Unknown certificate usage #{kind.inspect}. " \
                           "The contract declares #{Certificate::USAGES.map(&:inspect).join(" and ")}."
      end

      # Callers hold the mutex.
      def cached = fresh? ? @certificates : nil

      def fresh? = !@fetched_at.nil? && (now - @fetched_at) < @ttl

      def load!
        @certificates = Array(@connection.get(PATH).body).map { |payload| Certificate.from(payload) }.freeze
        @fetched_at = now
        @certificates
      end

      def nothing_valid(kind, moment)
        published = @certificates.flat_map(&:usage).uniq
        "No published KSeF certificate for usage #{kind.inspect} is valid at #{moment.iso8601}. " \
          "The list carries #{@certificates.size} certificate(s) covering #{published.inspect}. " \
          "If a rotation has just happened, PublicKeys#refresh! re-reads the list."
      end
    end
  end
end
