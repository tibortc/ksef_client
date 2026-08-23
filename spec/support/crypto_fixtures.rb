# frozen_string_literal: true

require "openssl"

# Stand-ins for the certificates `GET /security/public-key-certificates` publishes
# (docs/REFERENCE.md §10.2).
#
# The identifiers are computed the way §10.2 says the Ministry computes them —
# `certificateId` is the SHA-256 of the DER certificate and `publicKeyId` the SHA-256 of
# the DER `SubjectPublicKeyInfo`, both base64 — so the fixture states that claim rather
# than filling the fields with arbitrary strings. Whether the *live* API agrees is asserted
# in `spec/integration/crypto_spec.rb`, which is the only place it can be.
#
# Keypairs are memoised at module level: a 2048-bit RSA generation costs enough that a
# `let` would dominate the suite's runtime, and nothing here is mutated by a test.
module CryptoFixtures
  # Well inside the window every fixture below declares.
  NOW = Time.utc(2026, 8, 23, 12)

  VALID_FROM = "2024-07-11T12:23:56.0154302+00:00"
  VALID_TO = "2028-07-11T12:23:56.0154302+00:00"

  class << self
    def keypair = @keypair ||= OpenSSL::PKey::RSA.generate(2048)

    # A second, unrelated key — for the "wrapped under the wrong key" case, which is what
    # a stale `publicKeyId` produces in the wild.
    def other_keypair = @other_keypair ||= OpenSSL::PKey::RSA.generate(2048)

    # One element of the response array.
    def payload(usage: [Ksef::Crypto::Certificate::SYMMETRIC_KEY_ENCRYPTION],
                valid_from: VALID_FROM, valid_to: VALID_TO, key: keypair)
      der = x509(key).to_der
      {
        "certificate" => [der].pack("m0"),
        "certificateId" => base64_sha256(der),
        "publicKeyId" => base64_sha256(key.public_to_der),
        "validFrom" => valid_from,
        "validTo" => valid_to,
        "usage" => usage
      }
    end

    def certificate(**) = Ksef::Crypto::Certificate.from(payload(**))

    private

    def base64_sha256(bytes) = [OpenSSL::Digest::SHA256.digest(bytes)].pack("m0")

    def x509(key)
      @x509 ||= {}
      @x509[key.public_to_der] ||= issue(key)
    end

    # `CN = Ministerstwo Finansów`, as §10.2 records the real ones carrying.
    def issue(key)
      name = OpenSSL::X509::Name.parse("/C=PL/CN=Ministerstwo Finansów")
      certificate = OpenSSL::X509::Certificate.new
      certificate.version = 2
      certificate.serial = 0x515345460001
      certificate.subject = name
      certificate.issuer = name
      certificate.public_key = key.public_key
      window(certificate)
      certificate.sign(key, OpenSSL::Digest.new("SHA256"))
    end

    def window(certificate)
      certificate.not_before = Time.utc(2024, 7, 11)
      certificate.not_after = Time.utc(2028, 7, 11)
    end
  end
end
