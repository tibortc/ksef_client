# frozen_string_literal: true

require "openssl"

# Self-signed certificates of the kind the TEST environment accepts
# (docs/REFERENCE.md §4.6 — permitted on TEST only).
#
# Memoised at module level on purpose: generating a 2048-bit RSA key takes long enough that
# a `let` would dominate the suite's runtime, and nothing here is mutated by a test.
module SigningFixtures
  class << self
    # Mirrors `CertificateUtils.GetPersonalCertificate` in `ksef-client-csharp`: a natural
    # person's certificate carrying the NIP in `serialNumber` as `TINPL-<nip>`, which is one
    # of the two patterns §4.4 records as recognised.
    def personal(nip: "5265877635")
      @personal ||= {}
      @personal[nip] ||= issue(
        "/C=PL/CN=Jan Kowalski/GN=Jan/SN=Kowalski/serialNumber=TINPL-#{nip}"
      )
    end

    # The organisation-seal equivalent: NIP in `organizationIdentifier` as `VATPL-<nip>`,
    # and no `givenName`/`surname`, which §4.4 records as forbidden for a seal.
    def seal(nip: "5265877635")
      @seal ||= {}
      @seal[nip] ||= issue("/C=PL/O=Kowalski sp. z o.o./CN=Kowalski/organizationIdentifier=VATPL-#{nip}")
    end

    # A key that is valid but belongs to nobody in particular, for the mismatch case.
    def unrelated_key
      @unrelated_key ||= OpenSSL::PKey::RSA.generate(2048)
    end

    private

    def issue(subject)
      key = OpenSSL::PKey::RSA.generate(2048)
      { certificate: self_sign(OpenSSL::X509::Name.parse(subject), key), key: key }
    end

    # An hour either side: long enough that nothing flakes, short enough that these are
    # obviously throwaway.
    def set_validity(certificate, window: 3600)
      certificate.not_before = Time.now - window
      certificate.not_after = Time.now + window
    end

    def self_sign(name, key)
      OpenSSL::X509::Certificate.new.tap do |certificate|
        certificate.version = 2
        certificate.serial = 0x1122334455
        certificate.subject = name
        certificate.issuer = name
        certificate.public_key = key.public_key
        set_validity(certificate)
        certificate.sign(key, OpenSSL::Digest.new("SHA256"))
      end
    end
  end
end
