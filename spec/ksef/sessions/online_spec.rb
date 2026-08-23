# frozen_string_literal: true

require_relative "../../support/crypto_fixtures"

RSpec.describe Ksef::Sessions::Online do
  subject(:sessions) { described_class.new(connection, "access.jwt") }

  let(:connection) { Ksef::HTTP::Connection.build(Ksef::Configuration.new(env: :test)) }
  let(:encryptor) { Ksef::Crypto::Encryptor.generate }
  let(:reference) { "20260823-SO-1234567890-1234567890-AB" }

  # Methods rather than `let`s: the fixture memoises underneath, and the group is at the
  # memoised-helper limit with the three above.
  def base = "https://api-test.ksef.mf.gov.pl/v2"

  def certificate = CryptoFixtures.certificate

  def json(body, status: 200)
    { status: status, body: JSON.dump(body), headers: { "Content-Type" => "application/json" } }
  end

  def opened
    described_class::Session.new(reference_number: reference, valid_until: nil, encryptor: encryptor)
  end

  # Asserts a POST to `url` was made and hands back its parsed body, which keeps every
  # assertion below a plain comparison. Where a test makes several requests to the same
  # URL, this yields the last.
  def sent_to(url)
    captured = nil
    matcher = a_request(:post, url).with do |request|
      captured = request.body.to_s.empty? ? {} : JSON.parse(request.body)
      true
    end
    expect(matcher).to have_been_made
    captured
  end

  describe "#open" do
    subject(:session) { sessions.open(encryptor: encryptor, certificate: certificate) }

    let(:url) { "#{base}/sessions/online" }

    before do
      stub_request(:post, "#{base}/sessions/online").to_return(
        json({ "referenceNumber" => reference, "validUntil" => "2026-08-24T00:00:00Z" }, status: 201)
      )
    end

    it "returns the session reference and its expiry" do
      expect(session.reference_number).to eq(reference)
      expect(session.valid_until).to eq(Time.utc(2026, 8, 24))
    end

    it "sends the FA(3) form code triple by default" do
      session

      expect(sent_to(url)["formCode"])
        .to eq("systemCode" => "FA (3)", "schemaVersion" => "1-0E", "value" => "FA")
    end

    it "sends the wrapped key, the IV and the key selector as EncryptionInfo" do
      session
      encryption = sent_to(url)["encryption"]

      expect(encryption.keys).to contain_exactly(
        "encryptedSymmetricKey", "initializationVector", "publicKeyId"
      )
      expect(encryption["publicKeyId"]).to eq(certificate.public_key_id)
    end

    # §14.1 at the level it actually matters: the IV is a field of *this* request and
    # travels once, not per invoice and not glued to any ciphertext.
    it "sends the IV once here, decodable back to the encryptor's own IV" do
      session

      expect(Ksef::Crypto.decode(sent_to(url).dig("encryption", "initializationVector")))
        .to eq(encryptor.iv)
    end

    it "wraps a 32-byte key that KSeF's private key can recover" do
      session
      wrapped = Ksef::Crypto.decode(sent_to(url).dig("encryption", "encryptedSymmetricKey"))

      expect(CryptoFixtures.keypair.decrypt(wrapped, Ksef::Crypto::OAEP).bytesize).to eq(32)
    end

    # §14.6 — undocumented in the contract, sent by both official clients, and load-bearing
    # because this gem pins upo-v4-3.xsd and nothing else.
    it "asks for the UPO version whose schema this gem bundles" do
      session

      expect(a_request(:post, url).with(headers: { "X-KSeF-Feature" => "upo-v4-3" }))
        .to have_been_made
    end

    it "omits the header when explicitly told to, accepting the server default" do
      sessions.open(encryptor: encryptor, certificate: certificate, upo_version: nil)
      matcher = a_request(:post, url).with do |request|
        !request.headers.key?("X-Ksef-Feature")
      end

      expect(matcher).to have_been_made
    end

    it "accepts another declared schema" do
      sessions.open(encryptor: encryptor, certificate: certificate, form_code: :fa_rr1)

      expect(sent_to(url).dig("formCode", "systemCode")).to eq("FA_RR (1)")
    end

    it "accepts an explicit triple" do
      sessions.open(encryptor: encryptor, certificate: certificate,
                    form_code: { systemCode: "FA (2)", schemaVersion: "1-0E", value: "FA" })

      expect(sent_to(url).dig("formCode", "systemCode")).to eq("FA (2)")
    end

    it "refuses an undeclared form code rather than letting KSeF reject it" do
      expect { sessions.open(encryptor: encryptor, certificate: certificate, form_code: :fa4) }
        .to raise_error(Ksef::ValidationError, /Unknown form code :fa4/)
    end

    it "presents the access token" do
      session

      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer access.jwt" }))
        .to have_been_made
    end
  end

  describe "#send_invoice" do
    let(:xml) { "<Faktura>zażółć gęślą</Faktura>" }
    let(:url) { "#{base}/sessions/online/#{reference}/invoices" }

    before do
      stub_request(:post, "#{base}/sessions/online/#{reference}/invoices")
        .to_return(json({ "referenceNumber" => "20260823-FI-9999999999-9999999999-CD" }, status: 202))
    end

    it "returns the invoice's own reference number, not the session's" do
      result = sessions.send_invoice(opened, xml)

      expect(result.reference_number).to eq("20260823-FI-9999999999-9999999999-CD")
      expect(result.to_s).not_to eq(reference)
    end

    # §11.1 — four integrity values, and the two hashes must be over different artifacts.
    it "sends the hash and size of both the plaintext and the ciphertext" do
      sessions.send_invoice(opened, xml)
      body = sent_to(url)

      expect(body.keys).to contain_exactly(
        "invoiceHash", "invoiceSize", "encryptedInvoiceHash", "encryptedInvoiceSize",
        "encryptedInvoiceContent"
      )
      expect(body["invoiceHash"]).not_to eq(body["encryptedInvoiceHash"])
      expect(body["invoiceSize"]).to be < body["encryptedInvoiceSize"]
    end

    it "measures the plaintext in bytes, not characters" do
      sessions.send_invoice(opened, xml)

      expect(sent_to(url)["invoiceSize"]).to eq(xml.bytesize)
      expect(xml.bytesize).to be > xml.size
    end

    it "hashes each artifact over the bytes it actually sends" do
      sessions.send_invoice(opened, xml)
      body = sent_to(url)
      ciphertext = Ksef::Crypto.decode(body["encryptedInvoiceContent"])

      expect(body["invoiceHash"]).to eq(Ksef::Crypto::Digest.of(xml).base64)
      expect(body["encryptedInvoiceHash"]).to eq(Ksef::Crypto::Digest.of(ciphertext).base64)
      expect(body["encryptedInvoiceSize"]).to eq(ciphertext.bytesize)
    end

    # The session's key, not a fresh one: a different key means status 435 arriving
    # asynchronously, which is why the encryptor is bound to the session.
    it "encrypts under the session's own key, so the payload decrypts with it" do
      sessions.send_invoice(opened, xml)
      ciphertext = Ksef::Crypto.decode(sent_to(url)["encryptedInvoiceContent"])

      expect(encryptor.decrypt(ciphertext).force_encoding("UTF-8")).to eq(xml)
    end

    it "accepts anything that serialises itself" do
      document = Struct.new(:to_xml).new(xml)
      sessions.send_invoice(opened, document)

      expect(sent_to(url)["invoiceSize"]).to eq(xml.bytesize)
    end

    it "omits the optional fields unless asked" do
      sessions.send_invoice(opened, xml)

      expect(sent_to(url)).not_to have_key("offlineMode")
      expect(sent_to(url)).not_to have_key("hashOfCorrectedInvoice")
    end

    it "passes the offline-mode declaration and a corrected-invoice hash through" do
      sessions.send_invoice(opened, xml, offline_mode: true, corrected_invoice_hash: "abc=")
      body = sent_to(url)

      expect(body["offlineMode"]).to be(true)
      expect(body["hashOfCorrectedInvoice"]).to eq("abc=")
    end
  end

  describe "#close" do
    it "returns nil, since the API answers 204 with no body" do
      stub_request(:post, "#{base}/sessions/online/#{reference}/close").to_return(status: 204)

      expect(sessions.close(opened)).to be_nil
    end

    it "accepts a bare reference string as well as a session" do
      stub_request(:post, "#{base}/sessions/online/#{reference}/close").to_return(status: 204)
      sessions.close(reference)

      expect(a_request(:post, "#{base}/sessions/online/#{reference}/close")).to have_been_made
    end

    it "refuses a reference that could alter the request path" do
      expect { sessions.close("../../auth/sessions/current") }
        .to raise_error(Ksef::ValidationError, /not of the documented form/)
    end
  end

  describe described_class::Session do
    it "knows when its twelve hours are up" do
      session = described_class.new(
        reference_number: "R", valid_until: Time.utc(2026, 8, 24), encryptor: nil
      )

      expect(session.expired?(Time.utc(2026, 8, 23, 23, 59))).to be(false)
      expect(session.expired?(Time.utc(2026, 8, 24, 0, 1))).to be(true)
    end

    it "is never expired when the server sent no validUntil" do
      expect(described_class.new(reference_number: "R", valid_until: nil, encryptor: nil))
        .not_to be_expired
    end

    it "stringifies to its reference number" do
      expect(described_class.new(reference_number: "R", valid_until: nil, encryptor: nil).to_s)
        .to eq("R")
    end
  end

  describe "the credential" do
    it "asks an AccessToken for a bearer per request, so a refresh is picked up" do
      credential = instance_double(Ksef::Auth::AccessToken)
      allow(credential).to receive(:bearer).and_return("first.jwt", "second.jwt")
      stub_request(:post, "#{base}/sessions/online/#{reference}/close").to_return(status: 204)

      client = described_class.new(connection, credential)
      client.close(opened)
      client.close(opened)

      expect(a_request(:post, "#{base}/sessions/online/#{reference}/close")
        .with(headers: { "Authorization" => "Bearer second.jwt" })).to have_been_made
    end
  end
end
