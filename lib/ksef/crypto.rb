# frozen_string_literal: true

require "openssl"
require "time"

module Ksef
  # Encryption of the payloads KSeF requires to be encrypted (docs/REFERENCE.md §10).
  #
  # Every parameter here is *ledgered*, not chosen. They come from
  # `sesja-interaktywna.md` and `uwierzytelnianie.md` §2.2 — first-tier documentation —
  # corroborated against both reference clients' cryptography services. Do not adjust one
  # without re-reading §10 first; a mismatch here does not fail loudly, it produces a
  # payload KSeF silently cannot decrypt.
  #
  # ## What lives where
  #
  # This module holds the primitives: the algorithm identifiers, base64, SHA-256 and the
  # one RSA operation. {Crypto::Certificate} and {Crypto::PublicKeys} deal with the keys
  # the Ministry publishes, {Crypto::Encryptor} with a session's symmetric key, and
  # {Crypto::Digest} with the integrity metadata that travels beside every payload.
  #
  # Nothing here knows an API field name. Mapping to `EncryptionInfo` and
  # `SendInvoiceRequest` is {Crypto::Encryptor}'s single concession to the wire format,
  # and building the requests themselves belongs to the session layer.
  module Crypto
    # AES-256-CBC with PKCS#7 padding: 256-bit key, 128-bit IV, 128-bit block (§10.1).
    # The Java client names the same thing `AES/CBC/PKCS5Padding`; for a 16-byte block
    # PKCS#5 and PKCS#7 are identical, so that is not a divergence.
    CIPHER = "aes-256-cbc"
    KEY_BYTES = 32
    IV_BYTES = 16
    BLOCK_BYTES = 16

    # RSAES-OAEP with SHA-256 **and** MGF1-SHA-256 (§10.1), used for both the symmetric
    # key wrap and the KSeF-token payload of §4.5.
    #
    # All three options have to be stated. `OpenSSL::PKey::RSA#public_encrypt` cannot
    # express an MGF1 digest at all, and OpenSSL's default MGF1 digest is SHA-1 — so
    # setting `rsa_oaep_md` alone yields OAEP-SHA256-with-MGF1-SHA1, which is a *different
    # scheme* that KSeF cannot unwrap. It fails at the far end, not here.
    OAEP = { rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256" }.freeze

    # Longest plaintext RSAES-OAEP can carry for a 2048-bit key: `k - 2*hLen - 2`, so
    # `256 - 64 - 2`. Stated because it pins the digest — with SHA-1 the figure would be
    # 214 — and because it is the reason both encrypted payloads here are small ones.
    MAX_OAEP_PLAINTEXT_BYTES = 190

    class << self
      # Strict base64, no line breaks, for everything this gem *sends*.
      def encode(bytes) = [bytes].pack("m0")

      # Lenient base64 for everything it *receives*, which is the asymmetry that matters:
      # `"m0"` raises on a line break, and how a server wraps a long value is its business.
      # Nothing is silently accepted as a result — a certificate that decodes to garbage
      # fails in `OpenSSL::X509::Certificate.new`, with a better message than we would give.
      def decode(text) = text.to_s.unpack1("m")

      # @return [String] the raw 32-byte digest; {Digest} is the base64-and-size form
      def sha256(bytes) = OpenSSL::Digest::SHA256.digest(bytes)

      # @param public_key [OpenSSL::PKey::RSA]
      # @return [String] raw ciphertext, one RSA block wide
      def rsa_encrypt(plaintext, public_key) = public_key.encrypt(plaintext, OAEP)
    end
  end
end
