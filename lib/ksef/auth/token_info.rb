# frozen_string_literal: true

module Ksef
  module Auth
    # A JWT and its expiry, the contract's `TokenInfo` (docs/REFERENCE.md §4.2).
    TokenInfo = Data.define(:token, :valid_until)

    # Reopened rather than using a `Data.define` block so `REDACTED` lands on the class.
    class TokenInfo
      REDACTED = "[REDACTED]"

      def self.from(payload)
        return nil if payload.nil?

        new(token: payload["token"], valid_until: Ksef::Auth.time(payload["validUntil"]))
      end

      def expired?(now = Time.now) = !valid_until.nil? && valid_until <= now

      # Both redacted, and `#to_s` deliberately so: these are bearer credentials, and
      # returning the raw JWT here would make `"...#{token_info}"` in any log line leak a
      # live one (DESIGN.md §4.5). Reaching for the value is an explicit `#token` call.
      def to_s = REDACTED
      def inspect = "#<data Ksef::Auth::TokenInfo token=#{REDACTED} valid_until=#{valid_until.inspect}>"
    end
  end
end
