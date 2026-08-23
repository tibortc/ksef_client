# frozen_string_literal: true

require_relative "../../support/crypto_fixtures"

RSpec.describe Ksef::Crypto::Certificate do
  subject(:certificate) { CryptoFixtures.certificate }

  describe ".from" do
    it "maps every field of the contract's PublicKeyCertificate" do
      payload = CryptoFixtures.payload

      expect(certificate.certificate).to eq(payload["certificate"])
      expect(certificate.certificate_id).to eq(payload["certificateId"])
      expect(certificate.public_key_id).to eq(payload["publicKeyId"])
      expect(certificate.usage).to eq([described_class::SYMMETRIC_KEY_ENCRYPTION])
    end

    # KSeF sends seven fractional digits and an explicit offset, which is more than the
    # usual `date-time`. Asserted down to the sub-second part so a lenient-but-lossy parse
    # would show up here.
    it "parses the validity window, sub-second precision and offset included" do
      expect(certificate.valid_from.utc.strftime("%FT%T")).to eq("2024-07-11T12:23:56")
      expect(certificate.valid_from.nsec).to eq(15_430_200)
      expect(certificate.valid_to.utc.strftime("%FT%T")).to eq("2028-07-11T12:23:56")
    end

    it "passes a Time through unchanged" do
      moment = Time.utc(2026, 1, 1)

      expect(described_class.from(CryptoFixtures.payload.merge("validFrom" => moment)).valid_from).to eq(moment)
    end

    it "tolerates a missing usage array rather than raising" do
      expect(described_class.from({}).usage).to eq([])
    end
  end

  describe "#usable_for?" do
    it "is true for a declared usage" do
      expect(certificate).to be_usable_for(described_class::SYMMETRIC_KEY_ENCRYPTION)
    end

    # The two usages are not interchangeable: one wraps session keys, the other KSeF tokens.
    it "is false for the other usage, even though both are RSA keys" do
      expect(certificate).not_to be_usable_for(described_class::KSEF_TOKEN_ENCRYPTION)
    end

    it "recognises a certificate declaring both" do
      both = CryptoFixtures.certificate(usage: described_class::USAGES)

      expect(described_class::USAGES.all? { |kind| both.usable_for?(kind) }).to be(true)
    end
  end

  describe "#valid_at?" do
    it "is true inside the window" do
      expect(certificate.valid_at?(CryptoFixtures::NOW)).to be(true)
    end

    it "is false before it opens and after it closes" do
      expect(certificate.valid_at?(Time.utc(2024, 1, 1))).to be(false)
      expect(certificate.valid_at?(Time.utc(2029, 1, 1))).to be(false)
    end

    it "is inclusive at both edges" do
      expect(certificate.valid_at?(certificate.valid_from)).to be(true)
      expect(certificate.valid_at?(certificate.valid_to)).to be(true)
    end

    # Fail closed. An unparseable window must not read as "no constraint" — that would wrap
    # a payload with a key KSeF may already have withdrawn.
    it "refuses a certificate whose window did not parse" do
      broken = described_class.from(CryptoFixtures.payload.merge("validFrom" => "not a date"))

      expect(broken.valid_from).to be_nil
      expect(broken.valid_at?(CryptoFixtures::NOW)).to be(false)
    end

    it "refuses one with no window at all" do
      expect(described_class.from({}).valid_at?(CryptoFixtures::NOW)).to be(false)
    end
  end

  describe "#x509" do
    # The field is DER, base64-encoded, *without* PEM armour (§10.2), so it cannot be
    # handed to OpenSSL as text.
    it "parses the armour-less DER the contract sends" do
      expect(certificate.certificate).not_to include("BEGIN CERTIFICATE")
      expect(certificate.x509).to be_a(OpenSSL::X509::Certificate)
      expect(certificate.x509.subject.to_s).to include("Ministerstwo Finans")
    end

    it "raises on a certificate field that is not a certificate" do
      broken = described_class.from(CryptoFixtures.payload.merge("certificate" => "bm90IERFUg=="))

      expect { broken.x509 }.to raise_error(OpenSSL::OpenSSLError)
    end
  end

  describe "#encrypt" do
    it "wraps under the certificate's own key, using the ledgered OAEP parameters" do
      ciphertext = certificate.encrypt("a" * 32)

      expect(CryptoFixtures.keypair.decrypt(ciphertext, Ksef::Crypto::OAEP)).to eq("a" * 32)
    end

    it "cannot be unwrapped by an unrelated key, which is what a stale publicKeyId means" do
      ciphertext = certificate.encrypt("a" * 32)

      expect { CryptoFixtures.other_keypair.decrypt(ciphertext, Ksef::Crypto::OAEP) }
        .to raise_error(OpenSSL::OpenSSLError)
    end

    it "exposes the public key for a caller doing its own wrapping" do
      expect(certificate.public_key.public_to_der).to eq(CryptoFixtures.keypair.public_to_der)
    end
  end

  it "declares exactly the two usages the contract's enum carries" do
    expect(described_class::USAGES).to contain_exactly("KsefTokenEncryption", "SymmetricKeyEncryption")
  end
end
