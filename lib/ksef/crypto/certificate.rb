# frozen_string_literal: true

module Ksef
  module Crypto
    # One entry from `GET /security/public-key-certificates` — the contract's
    # `PublicKeyCertificate` (docs/REFERENCE.md §10.2).
    #
    # The Ministry publishes a list rather than a single key, and the entries are not
    # interchangeable: `usage` says what each may encrypt, and two entries can be valid at
    # once during a planned key rotation. {PublicKeys} applies the documented selection
    # rule; this class is the value object it selects from.
    Certificate = Data.define(:certificate, :certificate_id, :public_key_id, :valid_from, :valid_to, :usage)

    # Reopened rather than using a `Data.define` block so the usage constants land on the
    # class rather than on `Object`.
    class Certificate
      # The two members of the contract's `PublicKeyCertificateUsage` enum. Keeping them
      # here rather than as bare strings at call sites means a typo is a `NameError` at
      # load time instead of an empty selection at runtime.
      KSEF_TOKEN_ENCRYPTION = "KsefTokenEncryption"
      SYMMETRIC_KEY_ENCRYPTION = "SymmetricKeyEncryption"
      USAGES = [KSEF_TOKEN_ENCRYPTION, SYMMETRIC_KEY_ENCRYPTION].freeze

      def self.from(payload)
        new(
          certificate: payload["certificate"],
          certificate_id: payload["certificateId"],
          public_key_id: payload["publicKeyId"],
          valid_from: time(payload["validFrom"]),
          valid_to: time(payload["validTo"]),
          usage: Array(payload["usage"]).freeze
        )
      end

      # Parsed strictly here, unlike {Ksef::Auth.time}'s informational timestamps: these
      # two bound the window in which the key may be used, so an unparseable value must
      # not read as "no constraint". It becomes `nil`, and {#valid_at?} then refuses the
      # certificate outright — fail closed, since sending a payload wrapped with a lapsed
      # key is worse than declining to send one.
      def self.time(value)
        return value if value.is_a?(Time)

        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
      private_class_method :time

      # @param kind [String] one of {USAGES}
      def usable_for?(kind) = usage.include?(kind)

      def valid_at?(now = Time.now)
        return false if valid_from.nil? || valid_to.nil?

        now.between?(valid_from, valid_to)
      end

      # The contract ships the certificate as **DER, base64-encoded, without PEM armour**,
      # so it cannot be handed to OpenSSL as text.
      #
      # Not memoised: `Data` instances are frozen, and this is called once per session
      # open or authentication, where a DER parse is not worth caching around.
      #
      # @return [OpenSSL::X509::Certificate]
      def x509 = OpenSSL::X509::Certificate.new(Crypto.decode(certificate))

      # @return [OpenSSL::PKey::RSA]
      def public_key = x509.public_key

      # RSA-OAEP under this certificate's key. The plaintexts KSeF asks for are a 32-byte
      # symmetric key (§10.1) and a short `token|timestamp` string (§4.5), both far inside
      # {Crypto::MAX_OAEP_PLAINTEXT_BYTES}.
      #
      # @return [String] raw ciphertext; base64 it with {Crypto.encode} before sending
      def encrypt(plaintext) = Crypto.rsa_encrypt(plaintext, public_key)
    end
  end
end
