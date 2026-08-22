# frozen_string_literal: true

module Ksef
  module Auth
    # The response to `POST /auth/challenge` — the prologue to both authentication methods.
    #
    # `timestamp_ms` is not decoration: the KSeF-token flow encrypts `{token}|{timestampMs}`
    # and the timestamp acts as a nonce, so it must be the server's value rather than a
    # locally generated one (docs/REFERENCE.md §4.5).
    Challenge = Data.define(:challenge, :timestamp, :timestamp_ms, :client_ip)

    # Reopened rather than using a `Data.define` block, matching {Ksef::FA3::Invoice}: a
    # constant inside that block would be defined on `Object`, not on the class.
    class Challenge
      # Ten minutes from issue (§4).
      LIFETIME = 600

      def self.from(payload)
        new(
          challenge: payload["challenge"],
          timestamp: Ksef::Auth.time(payload["timestamp"]),
          timestamp_ms: payload["timestampMs"],
          client_ip: payload["clientIp"]
        )
      end

      # Worth checking before spending a signature on a challenge that has already lapsed.
      def expires_at = timestamp && (timestamp + LIFETIME)
      def expired?(now = Time.now) = !expires_at.nil? && expires_at <= now
      def to_s = challenge.to_s
    end
  end
end
