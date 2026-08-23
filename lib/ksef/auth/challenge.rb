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

      # Length 36, `\d{8}-CR-[A-F0-9]{10}-[A-F0-9]{10}-[A-F0-9]{2}` (§4.1). Lives here
      # rather than on the request documents because it describes a *challenge*, and both
      # authentication methods consume the same one — the XAdES document and the KSeF-token
      # JSON body would otherwise each carry their own copy.
      FORMAT = /\A\d{8}-CR-[A-F0-9]{10}-[A-F0-9]{10}-[A-F0-9]{2}\z/

      # Checked before a request is spent on the challenge, since a malformed or
      # copy-pasted one is the cheapest failure to catch locally.
      #
      # @param value [String]
      # @raise [Ksef::ValidationError]
      def self.validate_format!(value)
        return value if value.is_a?(String) && FORMAT.match?(value)

        raise ValidationError,
              "Challenge #{value.inspect} is malformed. Expected 36 characters as " \
              "YYYYMMDD-CR-XXXXXXXXXX-XXXXXXXXXX-XX with uppercase hex, exactly as returned by " \
              "POST /auth/challenge."
      end

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
