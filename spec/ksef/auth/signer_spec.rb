# frozen_string_literal: true

require "nokogiri"
require "openssl"
require_relative "../../support/signing_fixtures"

RSpec.describe Ksef::Auth::Signer do
  let(:certificate) { SigningFixtures.personal.fetch(:certificate) }
  let(:key) { SigningFixtures.personal.fetch(:key) }
  let(:signer) { described_class.new(certificate: certificate, key: key) }

  let(:request) do
    Ksef::Auth::TokenRequest.new(
      challenge: "20250604-CR-461EA5B000-537A6BA15D-D7", context_type: :nip, context_value: "5265877635"
    )
  end

  let(:signed) { signer.sign(request) }

  def namespaces = Ksef::Auth::Xades::XPATH_NAMESPACES

  def parse(xml) = Nokogiri::XML(xml)
  def at(xml, xpath) = parse(xml).at_xpath(xpath, namespaces)
  def sha256(bytes) = [OpenSSL::Digest::SHA256.digest(bytes)].pack("m0")

  # The document as the enveloped-signature transform leaves it for a verifier: everything
  # except the signature subtree.
  def without_signature(xml)
    document = parse(xml)
    document.at_xpath("//ds:Signature", namespaces).unlink
    document.canonicalize(described_class::C14N_MODE)
  end

  # These recompute every digest and the signature from the emitted bytes, deliberately
  # without reusing any of Signer's own code. A test that asked Signer to check its own
  # arithmetic would pass even if the arithmetic were wrong.
  describe "independent verification of the emitted signature" do
    it "produces a document digest a verifier would recompute identically" do
      expect(at(signed, "//ds:Reference[@URI='']/ds:DigestValue").text)
        .to eq(sha256(without_signature(signed)))
    end

    it "produces a SignedProperties digest a verifier would recompute identically" do
      properties = at(signed, "//xades:SignedProperties")

      expect(at(signed, "//ds:Reference[@Type]/ds:DigestValue").text)
        .to eq(sha256(properties.canonicalize(described_class::C14N_MODE)))
    end

    it "produces a SignatureValue that verifies against the embedded certificate" do
      signed_info = at(signed, "//ds:SignedInfo").canonicalize(described_class::C14N_MODE)
      signature = at(signed, "//ds:SignatureValue").text.unpack1("m0")
      embedded = OpenSSL::X509::Certificate.new(at(signed, "//ds:X509Certificate").text.unpack1("m0"))

      expect(embedded.public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signed_info)).to be(true)
    end

    it "embeds the certificate that actually signed" do
      embedded = OpenSSL::X509::Certificate.new(at(signed, "//ds:X509Certificate").text.unpack1("m0"))

      expect(embedded.to_der).to eq(certificate.to_der)
    end

    it "validates against the pinned xmldsig schema" do
      schema = Nokogiri::XML::Schema(
        File.read(File.expand_path("../../fixtures/xades/UBL-xmldsig-core-schema-2.1.xsd", __dir__),
                  encoding: "UTF-8")
      )

      expect(schema.validate(parse(at(signed, "//ds:Signature").to_xml))).to be_empty
    end
  end

  # The property that makes a signature worth anything.
  describe "tamper detection" do
    it "notices a changed payload" do
      tampered = signed.sub("<Nip>5265877635</Nip>", "<Nip>1111111111</Nip>")

      expect(sha256(without_signature(tampered)))
        .not_to eq(at(tampered, "//ds:Reference[@URI='']/ds:DigestValue").text)
    end

    it "notices a changed signing time" do
      tampered = signed.sub(%r{<xades:SigningTime>[^<]+</xades:SigningTime>},
                            "<xades:SigningTime>2020-01-01T00:00:00Z</xades:SigningTime>")
      properties = at(tampered, "//xades:SignedProperties")

      expect(sha256(properties.canonicalize(described_class::C14N_MODE)))
        .not_to eq(at(tampered, "//ds:Reference[@Type]/ds:DigestValue").text)
    end

    it "notices a re-signed SignedInfo, so SignatureValue cannot be lifted onto another document" do
      other = described_class.new(certificate: certificate, key: key).sign(
        Ksef::Auth::TokenRequest.new(
          challenge: "20250604-CR-461EA5B000-537A6BA15D-D7", context_type: :nip, context_value: "1111111111"
        )
      )
      grafted = signed.sub(
        %r{<ds:SignatureValue>[^<]+</ds:SignatureValue>},
        "<ds:SignatureValue>#{at(other, "//ds:SignatureValue").text}</ds:SignatureValue>"
      )
      signed_info = at(grafted, "//ds:SignedInfo").canonicalize(described_class::C14N_MODE)
      signature = at(grafted, "//ds:SignatureValue").text.unpack1("m0")

      expect(certificate.public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signed_info)).to be(false)
    end
  end

  # Every one of these appears in the Ministry's allow-list (§4.3). Asserted so that a
  # well-meaning change to a "more modern" algorithm has to be a deliberate one.
  describe "algorithm selection" do
    it "canonicalises with exclusive c14n" do
      expect(at(signed, "//ds:CanonicalizationMethod")["Algorithm"]).to eq(described_class::CANONICALIZATION)
    end

    it "signs with rsa-sha256" do
      expect(at(signed, "//ds:SignatureMethod")["Algorithm"]).to eq(described_class::SIGNATURE_METHOD)
    end

    it "digests with sha256 everywhere, including the certificate digest" do
      algorithms = parse(signed).xpath("//*[local-name()='DigestMethod']").map { |n| n["Algorithm"] }

      expect(algorithms).to all(eq(described_class::DIGEST_METHOD))
      expect(algorithms.size).to eq(3)
    end

    it "applies the enveloped-signature transform before canonicalising the document" do
      transforms = parse(signed)
                   .xpath("//ds:Reference[@URI='']/ds:Transforms/ds:Transform", namespaces)
                   .map { |n| n["Algorithm"] }

      expect(transforms).to eq([described_class::ENVELOPED_SIGNATURE, described_class::CANONICALIZATION])
    end

    it "marks the SignedProperties reference with the ETSI Type URI" do
      expect(at(signed, "//ds:Reference[@Type]")["Type"]).to eq(described_class::SIGNED_PROPERTIES_TYPE)
    end

    it "points that reference at the SignedProperties element by Id" do
      expect(at(signed, "//ds:Reference[@Type]")["URI"]).to eq("#SignedProperties")
      expect(at(signed, "//xades:SignedProperties")["Id"]).to eq("SignedProperties")
    end

    it "targets the QualifyingProperties at the signature by Id" do
      expect(at(signed, "//xades:QualifyingProperties")["Target"]).to eq("#Signature")
      expect(at(signed, "//ds:Signature")["Id"]).to eq("Signature")
    end
  end

  describe "qualifying properties" do
    it "backdates SigningTime by the clock skew, as the reference client does" do
      at_time = Time.utc(2026, 8, 22, 12, 0, 0)
      xml = described_class.new(certificate: certificate, key: key, signing_time: at_time).sign(request)

      expect(at(xml, "//xades:SigningTime").text).to eq("2026-08-22T11:59:00Z")
    end

    it "allows the skew to be turned off" do
      at_time = Time.utc(2026, 8, 22, 12, 0, 0)
      xml = described_class.new(certificate: certificate, key: key, signing_time: at_time, clock_skew: 0).sign(request)

      expect(at(xml, "//xades:SigningTime").text).to eq("2026-08-22T12:00:00Z")
    end

    it "records the SHA-256 of the certificate's DER form" do
      expect(at(signed, "//xades:CertDigest/*[local-name()='DigestValue']").text)
        .to eq(sha256(certificate.to_der))
    end

    it "records the issuer in RFC 2253 form and the serial in decimal" do
      expect(at(signed, "//*[local-name()='X509IssuerName']").text)
        .to eq(certificate.issuer.to_s(OpenSSL::X509::Name::RFC2253))
      expect(at(signed, "//*[local-name()='X509SerialNumber']").text).to eq(certificate.serial.to_s)
    end

    # The unprefixed elements inside xades:CertDigest belong to the xmldsig namespace, not
    # to XAdES. Getting this wrong yields a document that looks right and verifies nowhere.
    it "puts the unprefixed qualifying-property elements in the xmldsig namespace" do
      digest_value = at(signed, "//xades:CertDigest/*[local-name()='DigestValue']")

      expect(digest_value.namespace.href).to eq(described_class::DS)
      expect(digest_value.namespace.prefix).to be_nil
    end
  end

  describe "serialisation" do
    # The whole reason sign/1 works on bytes. If the output were re-indented after signing,
    # every digest above would still be internally consistent but wrong for the recipient.
    it "leaves the original document's bytes untouched, adding only the signature" do
      unsigned = request.to_xml
      prefix = unsigned.sub(%r{\n?</AuthTokenRequest>\s*\z}, "")

      expect(signed).to start_with(prefix)
    end

    it "appends the signature as the last child of the root" do
      expect(parse(signed).root.element_children.last.name).to eq("Signature")
    end

    it "keeps the document parseable and the declaration intact" do
      expect(signed).to start_with(%(<?xml version="1.0" encoding="UTF-8"?>))
      expect(parse(signed).errors).to be_empty
    end
  end

  describe "guardrails" do
    it "refuses a key that does not match the certificate" do
      expect { described_class.new(certificate: certificate, key: SigningFixtures.unrelated_key) }
        .to raise_error(Ksef::ValidationError, /private key does not match/)
    end

    it "refuses a document with no root element" do
      expect { signer.sign("<?xml version=\"1.0\"?>") }
        .to raise_error(Ksef::ValidationError, /no root element/)
    end

    # Validation has to happen before signing, because §14.5 means it can never happen
    # after. Catching it here saves a signature and gives a usable message.
    it "validates the document before signing it" do
      invalid = request.to_xml.sub("5265877635", "0000000000")

      expect { signer.sign(invalid) }.to raise_error(Ksef::ValidationError, /not schema-valid/)
    end

    it "can be told to skip validation" do
      invalid = request.to_xml.sub("5265877635", "0000000000")

      expect(signer.sign(invalid, validate: false)).to include("<ds:SignatureValue>")
    end

    it "accepts a raw XML String as readily as a TokenRequest" do
      expect(signer.sign(request.to_xml)).to include("<ds:Signature")
    end

    it "signs with an organisation seal certificate too" do
      seal = SigningFixtures.seal

      expect(described_class.new(certificate: seal.fetch(:certificate), key: seal.fetch(:key)).sign(request))
        .to include("<ds:SignatureValue>")
    end
  end

  # §14.4: `NipVatUe` and `PeppolId` cannot hold their real values under the pinned schema's
  # patterns, which are defective upstream. Signing delegates to the request's own
  # `#validate!`, so the failure names that rather than reading as bad input from the caller.
  describe "a context type whose schema pattern is defective upstream" do
    # A method rather than a `let`: the enclosing group is already at the memoised-helper
    # limit, and this is cheap to rebuild.
    def defective
      Ksef::Auth::TokenRequest.new(
        challenge: "20250604-CR-461EA5B000-537A6BA15D-D7",
        context_type: :nip_vat_ue, context_value: "5265877635-ATU12345678"
      )
    end

    it "explains that the failure may be upstream's fault, not the caller's" do
      expect { signer.sign(defective) }
        .to raise_error(Ksef::ValidationError, /defective upstream/)
    end

    # The §14.4 resolution: emit the natural value and let the server decide.
    it "still signs it with validate: false" do
      expect(signer.sign(defective, validate: false)).to include("SignatureValue")
    end
  end
end
