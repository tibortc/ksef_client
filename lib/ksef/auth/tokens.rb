# frozen_string_literal: true

module Ksef
  module Auth
    # The pair returned by `POST /auth/token/redeem` — the contract's
    # `AuthenticationTokensResponse`.
    #
    # Redemption is **single-use**: a second call with the same authentication token returns
    # 400 (docs/REFERENCE.md §4.2). Losing this object means repeating the whole flow,
    # signature included, so it is worth persisting deliberately rather than incidentally.
    Tokens = Data.define(:access_token, :refresh_token) do
      def self.from(payload)
        new(
          access_token: TokenInfo.from(payload["accessToken"]),
          refresh_token: TokenInfo.from(payload["refreshToken"])
        )
      end

      # Revocation is not immediate: an access token stays valid to its `exp` even after
      # permissions change (§4.2). Possession is not proof of current authorisation.
      def expired?(now = Time.now) = access_token.nil? || access_token.expired?(now)
    end
  end
end
