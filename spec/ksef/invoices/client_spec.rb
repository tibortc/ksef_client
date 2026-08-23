# frozen_string_literal: true

RSpec.describe Ksef::Invoices::Client do
  subject(:invoices) { described_class.new(connection, "access.jwt") }

  let(:connection) { Ksef::HTTP::Connection.build(Ksef::Configuration.new(env: :test)) }
  let(:number) { "5265877635-20250826-0100001AF629-AF" }

  def base = "https://api-test.ksef.mf.gov.pl/v2"

  describe "#download" do
    it "returns the invoice XML verbatim" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}")
        .to_return(status: 200, body: "<Faktura>zażółć</Faktura>",
                   headers: { "Content-Type" => "application/xml" })

      expect(invoices.download(number)).to eq("<Faktura>zażółć</Faktura>")
    end

    # The connection's JSON middleware matches on content type, so an application/xml body
    # is never parsed or re-encoded on the way through.
    it "does not parse the XML into anything" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}")
        .to_return(status: 200, body: "<Faktura/>", headers: { "Content-Type" => "application/xml" })

      expect(invoices.download(number)).to be_a(String)
    end

    it "requires the access token" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}").to_return(status: 200, body: "<x/>")
      invoices.download(number)

      expect(a_request(:get, "#{base}/invoices/ksef/#{number}")
        .with(headers: { "Authorization" => "Bearer access.jwt" })).to have_been_made
    end

    # Checked locally so a mistyped number fails on its CRC-8 rather than as an opaque 404
    # against a budget of only 64 requests an hour.
    it "validates the number before spending a request" do
      expect { invoices.download("5265877635-20250826-0100001AF629-00") }
        .to raise_error(Ksef::ValidationError, /checksum/)
      expect(a_request(:get, %r{/invoices/ksef/})).not_to have_been_made
    end

    # This route declares x-ms-meta-hash too (§5.5), and an archived invoice is a legal
    # document — so the free check is taken.
    it "verifies the published hash when the response carries one" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}").to_return(
        status: 200, body: "<Faktura/>",
        headers: { Ksef::UPO::HASH_HEADER => Ksef::Crypto::Digest.of("<Faktura/>").base64 }
      )

      expect(invoices.download(number)).to eq("<Faktura/>")
    end

    it "raises IntegrityError when the bytes do not match the published hash" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}").to_return(
        status: 200, body: "<Tampered/>",
        headers: { Ksef::UPO::HASH_HEADER => Ksef::Crypto::Digest.of("<Faktura/>").base64 }
      )

      expect { invoices.download(number) }.to raise_error(Ksef::IntegrityError)
    end

    it "accepts a response with no hash header rather than failing" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}").to_return(status: 200, body: "<x/>")

      expect(invoices.download(number)).to eq("<x/>")
    end

    it "accepts an already-parsed KsefNumber" do
      stub_request(:get, "#{base}/invoices/ksef/#{number}").to_return(status: 200, body: "<x/>")

      expect(invoices.download(Ksef::KsefNumber.parse(number))).to eq("<x/>")
    end

    it "asks an AccessToken for a bearer, so a refresh is picked up" do
      credential = instance_double(Ksef::Auth::AccessToken)
      allow(credential).to receive(:bearer).and_return("fresh.jwt")
      stub_request(:get, "#{base}/invoices/ksef/#{number}").to_return(status: 200, body: "<x/>")
      described_class.new(connection, credential).download(number)

      expect(a_request(:get, "#{base}/invoices/ksef/#{number}")
        .with(headers: { "Authorization" => "Bearer fresh.jwt" })).to have_been_made
    end
  end
end
