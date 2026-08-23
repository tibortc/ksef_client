# frozen_string_literal: true

module Ksef
  module Crypto
    # A session's symmetric key, and the AES-256-CBC encryption done under it
    # (docs/REFERENCE.md §10.1).
    #
    # ## The IV is not prefixed to the ciphertext
    #
    # This is the trap worth knowing about before reading anything else here.
    # `sesja-interaktywna.md` describes the IV as "dołączanego jako prefiks do szyfrogramu"
    # — prefixed to the ciphertext. **It is not**, and following that prose produces a
    # payload KSeF cannot decrypt. The IV travels once, as a discrete field of the
    # session-open request, and every per-invoice ciphertext is bare. Three higher-precedence
    # sources agree against the prose, the OpenAPI contract among them (§14.1) — and the
    # contract's own worked example settles it arithmetically: a 6480-byte invoice becomes
    # 6496 bytes encrypted. 6480 is a whole number of blocks, so PKCS#7 adds exactly one
    # block of padding; a prefixed IV would have made it 6512.
    #
    # So {#encrypt} returns bare ciphertext, and the IV is exposed separately for the
    # session-open request via {#encryption_info}.
    class Encryptor
      REDACTED = "[REDACTED]"

      # What {#seal} produces: the ciphertext to send, plus the integrity metadata for both
      # forms of the document. Bundled together because §11.1 requires the hash and size of
      # the plaintext *and* of the ciphertext, and hashing the wrong one of the two is a
      # silent error that only the server can detect.
      Sealed = Data.define(:ciphertext, :plaintext_digest, :ciphertext_digest) do
        # @return [String] base64 ciphertext, the wire form
        def content = Crypto.encode(ciphertext)
      end

      # The IV is not secret — it is sent to the API in the clear — so unlike the key it
      # has a reader. It is still kept out of {#inspect}, which DESIGN.md §4.5 requires.
      attr_reader :iv

      # A fresh key and IV from the CSPRNG. §10.1 records a per-session key as
      # *recommended* by the docs rather than required; recommended is reason enough.
      def self.generate
        cipher = OpenSSL::Cipher.new(CIPHER)
        new(key: cipher.random_key, iv: cipher.random_iv)
      end

      # @param key [String] 32 raw bytes
      # @param iv [String] 16 raw bytes
      # @raise [Ksef::CryptoError] on the wrong length
      def initialize(key:, iv:)
        @key = check("key", key, KEY_BYTES)
        @iv = check("iv", iv, IV_BYTES)
        freeze
      end

      # @param plaintext [String] the invoice XML, already serialised. Deliberately not
      #   `#to_xml`-coercing: what gets hashed has to be exactly what gets encrypted, so
      #   the bytes are settled one layer up.
      # @return [String] bare ciphertext, binary — see the class note on the IV
      def encrypt(plaintext) = transform(:encrypt, plaintext)

      # The inverse. KSeF never asks us to decrypt anything, so this exists for tests and
      # for a caller wanting to prove to itself that a payload round-trips before sending
      # it — which beats discovering a key mismatch from a rejected invoice.
      def decrypt(ciphertext) = transform(:decrypt, ciphertext)

      # Encrypt once, and measure both artifacts while they are in hand.
      #
      # @param plaintext [String]
      # @return [Sealed]
      def seal(plaintext)
        ciphertext = encrypt(plaintext)
        Sealed.new(
          ciphertext: ciphertext,
          plaintext_digest: Digest.of(plaintext),
          ciphertext_digest: Digest.of(ciphertext)
        )
      end

      # The contract's `EncryptionInfo`, as sent on `POST /sessions/online`,
      # `POST /sessions/batch` and `POST /invoices/exports`.
      #
      # `publicKeyId` is nullable in the contract but always sent here: it names *which*
      # published key did the wrapping, and without it a key rotation turns a decryptable
      # payload into an undecryptable one with nothing to diagnose it by (§10.2).
      #
      # @param certificate [Certificate] from {PublicKeys#symmetric_key_encryption}
      # @return [Hash]
      def encryption_info(certificate)
        {
          encryptedSymmetricKey: Crypto.encode(certificate.encrypt(@key)),
          initializationVector: Crypto.encode(@iv),
          publicKeyId: certificate.public_key_id
        }
      end

      # Redacted, and `#to_s` deliberately too: DESIGN.md §4.5 forbids leaking symmetric
      # keys and IVs at default log level, and `"key: #{encryptor}"` in someone's debug
      # line is exactly how that happens.
      def to_s = REDACTED
      def inspect = "#<Ksef::Crypto::Encryptor key=#{REDACTED} iv=#{REDACTED}>"

      private

      # A fresh cipher per call. `OpenSSL::Cipher` is stateful, so sharing one would make
      # this class unsafe to use from two threads and would leave a half-consumed cipher
      # behind after any exception.
      def transform(direction, data)
        cipher = OpenSSL::Cipher.new(CIPHER)
        cipher.public_send(direction)
        # On by default; stated because PKCS#7 is a ledgered parameter (§10.1) and not
        # something to leave to a library default.
        cipher.padding = 1
        cipher.key = @key
        cipher.iv = @iv
        cipher.update(data) + cipher.final
      end

      def check(name, value, expected)
        bytes = value.to_s
        unless bytes.bytesize == expected
          raise CryptoError,
                "The AES #{name} must be #{expected} bytes, got #{bytes.bytesize}. " \
                "KSeF requires AES-256-CBC (docs/REFERENCE.md §10.1); a shorter key would " \
                "silently select a weaker cipher."
        end

        # Frozen so a caller cannot mutate key material out from under a shared client.
        bytes.dup.freeze
      end
    end
  end
end
