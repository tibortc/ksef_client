# frozen_string_literal: true

module Ksef
  module Auth
    # A KSeF token and the context it authenticates into — the credential object of
    # DESIGN.md §8:
    #
    #     Ksef::Auth::Token.new(context_nip: "9999999999", token: ENV["KSEF_TOKEN"])
    #
    # A KSeF token is the second of the API's two authentication methods
    # (docs/REFERENCE.md §4). It is not a bearer token and is never sent as one: it is
    # RSA-OAEP-encrypted together with the challenge's timestamp and posted to
    # `POST /auth/ksef-token`, which starts the same asynchronous operation the XAdES flow
    # does and ends at the same `POST /auth/token/redeem`.
    #
    # ## It cannot be the first credential
    #
    # A KSeF token can only be *issued* after a one-time XAdES authentication
    # (`tokeny-ksef.md`; `POST /tokens` requires a bearer, `/auth/xades-signature` requires
    # nothing). So this class is the everyday path and {Signer} is the bootstrap — which is
    # why the certificate flow shipped first (§6a.2).
    #
    # Treat instances as secrets. `#to_s` and `#inspect` are redacted, and the token is
    # reachable only by the deliberate {#authentication_request}.
    class Token
      REDACTED = "[REDACTED]"

      # Only two of the contract's four `AuthenticationContextIdentifierType` values are
      # reachable here, and that is not a simplification: `tokeny-ksef.md` records that a
      # token can only be issued in a `Nip` or `InternalId` context, so a token for the
      # other two cannot exist to be presented (§4.1).
      CONTEXT_TYPES = { nip: "Nip", internal_id: "InternalId" }.freeze

      attr_reader :context_type, :context_value

      # @param token [String] the KSeF token, verbatim from `POST /tokens`
      # @param context_nip [String, nil] the NIP to authenticate into
      # @param internal_id [String, nil] an `InternalId` context instead — `<nip>-<5 digits>`
      # @raise [Ksef::ValidationError] on a missing token, or on neither/both contexts
      def initialize(token:, context_nip: nil, internal_id: nil)
        @token = validate_token(token)
        @context_type, @context_value = resolve_context(context_nip, internal_id)
        freeze
      end

      # The contract's `AuthenticationContextIdentifier`.
      def context_identifier = { type: CONTEXT_TYPES.fetch(context_type), value: context_value }

      # The `InitTokenAuthenticationRequest` body for `POST /auth/ksef-token`.
      #
      # Built here rather than inside {Client} for the same reason {Client#submit_xades}
      # takes an already-signed document: the HTTP layer maps requests and responses, and
      # the credential is what knows how to present itself.
      #
      # @param challenge [Challenge] the whole object, not just its string — see
      #   {#encrypted_token} for why the timestamp cannot be supplied locally
      # @param certificate [Ksef::Crypto::Certificate] from
      #   {Ksef::Crypto::PublicKeys#token_encryption}
      # @param allowed_ips [Hash, AuthorizationPolicy, nil] optional whitelist restricting
      #   which client IPs may use the resulting access token
      # @return [Hash]
      def authentication_request(challenge:, certificate:, allowed_ips: nil)
        request = {
          challenge: Challenge.validate_format!(challenge.to_s),
          contextIdentifier: context_identifier,
          encryptedToken: encrypted_token(challenge: challenge, certificate: certificate),
          publicKeyId: certificate.public_key_id
        }
        policy = AuthorizationPolicy.coerce(allowed_ips)
        policy ? request.merge(authorizationPolicy: { allowedIps: policy.to_h }) : request
      end

      # `{ksefToken}|{timestampMs}`, UTF-8, RSA-OAEP-encrypted and base64-encoded (§4.5).
      #
      # The timestamp is **not** decoration and **not** ours to generate: the docs are
      # explicit that it acts as a nonce, so that a captured ciphertext cannot be replayed
      # into a later session. It has to be the `timestampMs` the challenge response
      # carried, which is why this takes a {Challenge} and not a String — a locally
      # generated millisecond count will not match, and the authentication fails with
      # nothing to point at.
      #
      # @return [String] base64
      def encrypted_token(challenge:, certificate:)
        timestamp = challenge.respond_to?(:timestamp_ms) ? challenge.timestamp_ms : nil
        if timestamp.nil?
          raise AuthenticationError,
                "The KSeF-token flow needs the challenge's own timestampMs, so pass the " \
                "Ksef::Auth::Challenge returned by POST /auth/challenge rather than its string. " \
                "The timestamp is a replay nonce (docs/REFERENCE.md §4.5)."
        end

        Crypto.encode(certificate.encrypt("#{@token}|#{timestamp}"))
      end

      def to_s = REDACTED

      def inspect
        "#<Ksef::Auth::Token context=#{CONTEXT_TYPES.fetch(context_type)}:#{context_value} token=#{REDACTED}>"
      end

      private

      def validate_token(value)
        return value if value.is_a?(String) && !value.empty?

        raise ValidationError,
              "A KSeF token is required, got #{value.inspect}. It is issued by POST /tokens after a " \
              "one-time XAdES authentication (docs/REFERENCE.md §6a.2)."
      end

      def resolve_context(nip, internal_id)
        given = { nip: nip, internal_id: internal_id }.compact
        return given.first if given.size == 1

        raise ValidationError,
              "Pass exactly one of context_nip: or internal_id:, got #{given.keys.inspect}. " \
              "A KSeF token exists only in a Nip or InternalId context (docs/REFERENCE.md §4.1)."
      end
    end
  end
end
