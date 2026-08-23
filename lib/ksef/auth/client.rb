# frozen_string_literal: true

require "faraday"

module Ksef
  module Auth
    # The six HTTP calls of the authentication flow (docs/REFERENCE.md §4.2).
    #
    # Deliberately thin: it maps requests and responses and does nothing else. Deciding
    # *which* credential to present, and caching the result, belongs a layer up in
    # {Ksef::Client}, which does not exist yet.
    #
    # Namespaced `Ksef::Auth::Client` rather than folded into `Ksef::Client` so that each
    # subsystem's endpoints stay together, matching how the official clients are organised.
    #
    # Three of these calls are **unauthenticated** — the challenge and both authentication
    # submissions declare no `security` in the contract. Of the rest, {#status} and
    # {#redeem} take the temporary *authentication* token and {#refresh} takes the refresh
    # token, so the bearer is passed per call rather than held by the instance.
    class Client
      # Polling defaults. There is deliberately no timeout: on DEMO and PROD the operation
      # legitimately stays "in progress" while the certificate's status is checked with its
      # issuer over OCSP/CRL, and the docs say the duration depends on that issuer. A client
      # that gives up after a fixed interval reports failure for authentications that were
      # about to succeed (§4.2).
      POLL_INTERVAL = 2

      # @param connection [Faraday::Connection] usually from {Ksef::HTTP::Connection.build}
      def initialize(connection)
        @connection = connection
      end

      # @return [Challenge]
      def challenge
        Challenge.from(post("auth/challenge").body)
      end

      # Submits the XAdES-signed `AuthTokenRequest`. Returns `202 Accepted`; the operation
      # is asynchronous from here.
      #
      # @param signed_xml [String]
      # @param verify_certificate_chain [Boolean, nil] the contract's optional query flag
      # @return [Initiation]
      def submit_xades(signed_xml, verify_certificate_chain: nil)
        response = @connection.post("auth/xades-signature") do |request|
          request.params["verifyCertificateChain"] = verify_certificate_chain unless verify_certificate_chain.nil?
          request.headers["Content-Type"] = "application/xml"
          request.body = signed_xml
        end
        Initiation.from(response.body)
      end

      # Submits a KSeF-token authentication. Like {#submit_xades} this takes an
      # already-built request — {Token#authentication_request} assembles it, because the
      # encryption depends on which published key was selected and that is not this
      # layer's decision.
      #
      # A `400` here carries `21111` for a bad challenge or `21470` for a stale key
      # identifier; the latter is worth wrapping in
      # {Ksef::Crypto::PublicKeys#with_key_rotation}.
      #
      # @param request [Hash] the contract's `InitTokenAuthenticationRequest`
      # @return [Initiation]
      def submit_ksef_token(request)
        Initiation.from(post("auth/ksef-token", body: request).body)
      end

      # @param token [String, TokenInfo] the *authentication* token from {#submit_xades}
      # @return [OperationStatus]
      def status(reference_number, token:)
        OperationStatus.from(get("auth/#{reference_number}", token: token).body)
      end

      # Exchanges a completed authentication for the token pair. **Single-use** — a second
      # call with the same authentication token is a 400, so this is never auto-retried
      # (it is a POST, which the retry policy already excludes).
      #
      # @return [Tokens]
      def redeem(token:)
        Tokens.from(post("auth/token/redeem", token: token).body)
      end

      # @return [TokenInfo] a fresh access token
      def refresh(refresh_token:)
        TokenInfo.from(post("auth/token/refresh", token: refresh_token).body["accessToken"])
      end

      # Polls until the operation stops being in progress.
      #
      # @param interval [Numeric] seconds between polls
      # @param sleeper [#call] injected for tests; receives the interval
      # @yieldparam status [OperationStatus] after each poll, for progress reporting
      # @return [OperationStatus] the terminal status, successful or not
      def wait_until_complete(reference_number, token:, interval: POLL_INTERVAL, sleeper: method(:sleep))
        loop do
          current = status(reference_number, token: token)
          yield current if block_given?
          return current if current.terminal?

          sleeper.call(interval)
        end
      end

      # As {#wait_until_complete}, but insists on success.
      #
      # @raise [Ksef::AuthenticationError] carrying the server's own wording and details
      def authenticate!(reference_number, token:, **, &)
        result = wait_until_complete(reference_number, token: token, **, &)
        return result if result.success?

        detail = result.details.empty? ? "" : " (#{result.details.join("; ")})"
        raise AuthenticationError,
              "Authentication #{reference_number} failed with status #{result.code}: #{result.explain}#{detail}"
      end

      private

      def get(path, token: nil)
        @connection.get(path) { |request| authorize(request, token) }
      end

      def post(path, token: nil, body: nil)
        @connection.post(path) do |request|
          authorize(request, token)
          request.body = body unless body.nil?
        end
      end

      # The bearer differs per call: the authentication token for status and redemption,
      # the refresh token for refresh, and none at all for the first two. A {TokenInfo} or
      # a bare String both work — but the value has to be pulled out explicitly, because
      # `TokenInfo#to_s` redacts itself and interpolating one would send "[REDACTED]".
      def authorize(request, token)
        return if token.nil?

        value = token.is_a?(TokenInfo) ? token.token : token.to_s
        request.headers["Authorization"] = "Bearer #{value}"
      end
    end
  end
end
