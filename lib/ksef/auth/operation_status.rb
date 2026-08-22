# frozen_string_literal: true

module Ksef
  module Auth
    # The response to `GET /auth/{referenceNumber}` — the contract's
    # `AuthenticationOperationStatusResponse`.
    OperationStatus = Data.define(
      :code, :description, :details, :authentication_method, :started_at,
      :token_redeemed, :last_refresh_at, :refresh_token_valid_until
    ) do
      def self.from(payload)
        status = payload["status"] || {}
        new(
          code: status["code"],
          description: status["description"],
          details: Array(status["details"]).freeze,
          authentication_method: payload["authenticationMethod"],
          started_at: Ksef::Auth.time(payload["startDate"]),
          token_redeemed: payload["isTokenRedeemed"],
          last_refresh_at: Ksef::Auth.time(payload["lastTokenRefreshDate"]),
          refresh_token_valid_until: Ksef::Auth.time(payload["refreshTokenValidUntil"])
        )
      end

      def in_progress? = Status.in_progress?(code)
      def success? = Status.success?(code)
      def terminal? = Status.terminal?(code)
      def retryable? = Status.retryable?(code)

      # Prefers the server's own wording; falls back to our table when it sends none.
      def explain = description.to_s.empty? ? Status.describe(code) : description
    end
  end
end
