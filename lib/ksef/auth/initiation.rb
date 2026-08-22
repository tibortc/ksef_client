# frozen_string_literal: true

module Ksef
  module Auth
    # The `202 Accepted` from `POST /auth/xades-signature` — the contract's
    # `AuthenticationInitResponse`.
    #
    # The token here is the short-lived *authentication* token, not an access token. It
    # authorises exactly two follow-up calls: checking the operation's status, and redeeming
    # it for the real pair. Confusing the two is the obvious mistake in this flow (§4.2).
    Initiation = Data.define(:reference_number, :authentication_token) do
      def self.from(payload)
        new(
          reference_number: payload["referenceNumber"],
          authentication_token: TokenInfo.from(payload["authenticationToken"])
        )
      end

      def token = authentication_token&.token
    end
  end
end
