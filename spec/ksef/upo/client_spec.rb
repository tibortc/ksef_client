# frozen_string_literal: true

RSpec.describe Ksef::UPO::Client do
  subject(:upo) { described_class.new(connection, "access.jwt", storage: storage) }

  let(:config) { Ksef::Configuration.new(env: :test) }
  let(:connection) { Ksef::HTTP::Connection.build(config) }
  let(:storage) { Ksef::HTTP::Connection.storage(config) }
  let(:session_ref) { "20260823-SO-1234567890-1234567890-AB" }

  def base = "https://api-test.ksef.mf.gov.pl/v2"

  def link = "https://ksefstorage.blob.core.windows.net/upo/abc?sig=PRESIGNED"

  # A stand-in for the real thing; the six pinned upstream examples are used by the
  # validator specs, where their content matters.
  def xml = "<Potwierdzenie>UPO</Potwierdzenie>"

  def hash_of(bytes) = Ksef::Crypto::Digest.of(bytes).base64

  def page(url: link, expires_at: nil, reference: "20260823-EU-1-1-ZZ")
    Ksef::Sessions::UpoPage.new(reference_number: reference, download_url: url, expires_at: expires_at)
  end

  describe "#download" do
    it "returns the bytes exactly as received" do
      stub_request(:get, link).to_return(status: 200, body: xml,
                                         headers: { Ksef::UPO::HASH_HEADER => hash_of(xml) })
      document = upo.download(page)

      expect(document.xml).to eq(xml)
      expect(document.source).to eq(:storage)
      expect(document.verified?).to be(true)
    end

    # §14.2, and the whole reason a second connection exists: sending the access token to
    # third-party storage would leak a live KSeF credential.
    it "sends no Authorization header to the pre-signed link" do
      stub_request(:get, link).to_return(status: 200, body: xml,
                                         headers: { Ksef::UPO::HASH_HEADER => hash_of(xml) })
      upo.download(page)
      matcher = a_request(:get, link).with { |request| !request.headers.key?("Authorization") }

      expect(matcher).to have_been_made
    end

    it "raises IntegrityError when the bytes do not match the published hash" do
      stub_request(:get, link).to_return(status: 200, body: "<Potwierdzenie>TAMPERED</Potwierdzenie>",
                                         headers: { Ksef::UPO::HASH_HEADER => hash_of(xml) })

      expect { upo.download(page) }
        .to raise_error(Ksef::IntegrityError, /corrupted transfer, not a bad request/)
    end

    # The metered route publishes no hash, so "no hash" cannot mean "failed" — otherwise
    # every API-route fetch would raise. The distinction lives in #verifiable?.
    it "accepts a response with no published hash rather than failing" do
      stub_request(:get, link).to_return(status: 200, body: xml)
      document = upo.download(page)

      expect(document.verifiable?).to be(false)
      expect(document.xml).to eq(xml)
    end

    it "accepts a bare URL as well as a page" do
      stub_request(:get, link).to_return(status: 200, body: xml)

      expect(upo.download(link).size).to eq(xml.bytesize)
    end

    it "refuses a page with no link at all" do
      expect { upo.download(page(url: nil)) }
        .to raise_error(Ksef::ValidationError, /No download URL/)
    end

    # §9 keeps this open: whether the live API returns the field absolute or host-relative is
    # unverified, and srodowiska.md says only that the host matches the environment called.
    describe "a host-relative downloadUrl" do
      it "is resolved against the API host rather than guessed at" do
        stub_request(:get, "#{base}/relative/upo").to_return(status: 200, body: xml)

        expect(upo.download(page(url: "/v2/relative/upo")).xml).to eq(xml)
      end

      it "leaves an absolute URL untouched, host and all" do
        stub_request(:get, link).to_return(status: 200, body: xml)
        upo.download(page)

        expect(a_request(:get, link)).to have_been_made
      end

      # A URL this gem did not construct, so it may be anything. Failing with our own error
      # beats letting URI::InvalidURIError escape from a UPO download.
      it "reports a malformed URL as a ValidationError rather than a URI error" do
        expect { upo.download(page(url: "http://exa mple/upo")) }
          .to raise_error(Ksef::ValidationError, /Malformed UPO download URL/)
      end
    end
  end

  describe "the metered API routes" do
    # The contract declares x-ms-meta-hash on all three metered UPO routes as well as the
    # pre-signed link (§5.5). An earlier version of the client threw it away here, on a false
    # premise; discarding a free integrity check on legal proof of receipt is a bad trade.
    it "verifies the published hash on the metered route too" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: xml, headers: { Ksef::UPO::HASH_HEADER => hash_of(xml) })
      document = upo.collective(session_ref, "20260823-EU-1-1-ZZ")

      expect(document.verifiable?).to be(true)
      expect(document.verified?).to be(true)
    end

    it "raises IntegrityError on the metered route when the bytes do not match" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: "<Tampered/>",
                   headers: { Ksef::UPO::HASH_HEADER => hash_of(xml) })

      expect { upo.collective(session_ref, "20260823-EU-1-1-ZZ") }
        .to raise_error(Ksef::IntegrityError)
    end

    # Absent header means unverifiable, not corrupt — otherwise a response that legitimately
    # omits it would look like tampering.
    it "accepts a metered response with no header as unverifiable" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: xml)

      expect(upo.collective(session_ref, "20260823-EU-1-1-ZZ").verifiable?).to be(false)
    end

    it "fetches a collective UPO by session and UPO reference" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: xml)
      document = upo.collective(session_ref, "20260823-EU-1-1-ZZ")

      expect(document.source).to eq(:api)
      expect(document.xml).to eq(xml)
    end

    it "presents the access token on the metered route, unlike the storage link" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: xml)
      upo.collective(session_ref, "20260823-EU-1-1-ZZ")

      expect(a_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .with(headers: { "Authorization" => "Bearer access.jwt" })).to have_been_made
    end

    it "fetches one invoice's UPO by its submission reference" do
      invoice_ref = "20260823-FI-9-9-CD"
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}/upo")
        .to_return(status: 200, body: xml)

      expect(upo.for_invoice(session_ref, invoice_ref).xml).to eq(xml)
    end

    it "fetches one invoice's UPO by KSeF number" do
      number = "5265877635-20250826-0100001AF629-AF"
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/ksef/#{number}/upo")
        .to_return(status: 200, body: xml)

      expect(upo.for_ksef_number(session_ref, number).xml).to eq(xml)
    end

    # Parsed before use, so a mistyped number fails on its checksum here rather than as an
    # opaque 404 from the far end.
    it "rejects a KSeF number whose checksum is wrong before making a request" do
      expect { upo.for_ksef_number(session_ref, "5265877635-20250826-0100001AF629-00") }
        .to raise_error(Ksef::ValidationError, /checksum/)
      expect(a_request(:get, %r{/invoices/ksef/})).not_to have_been_made
    end

    it "refuses a reference that could alter the request path" do
      expect { upo.collective(session_ref, "../../auth/sessions/current") }
        .to raise_error(Ksef::ValidationError, /not of the documented form/)
    end
  end

  describe "#fetch" do
    # The link is unmetered and hash-verified; the API route spends a budget where
    # GET /sessions already allows only 10/min. So prefer the link — the §14.2 resolution.
    it "prefers the unmetered link when it is still valid" do
      stub_request(:get, link).to_return(status: 200, body: xml,
                                         headers: { Ksef::UPO::HASH_HEADER => hash_of(xml) })
      document = upo.fetch(page(expires_at: Time.now + 600), session_reference: session_ref)

      expect(document.source).to eq(:storage)
      expect(a_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ"))
        .not_to have_been_made
    end

    it "falls back to the metered route once the link has expired" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: xml)
      document = upo.fetch(page(expires_at: Time.now - 60), session_reference: session_ref)

      expect(document.source).to eq(:api)
      expect(a_request(:get, link)).not_to have_been_made
    end

    it "falls back when there is no link at all" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/upo/20260823-EU-1-1-ZZ")
        .to_return(status: 200, body: xml)

      expect(upo.fetch(page(url: nil), session_reference: session_ref).source).to eq(:api)
    end
  end

  describe "the storage connection" do
    # Built without a base URL on purpose, so nothing can accidentally resolve a relative
    # path against the API host and send it credential-free, or vice versa.
    it "carries no bearer and no base URL" do
      expect(storage.headers).not_to have_key("Authorization")
      expect(storage.url_prefix.to_s).not_to include("ksef.mf.gov.pl")
    end

    it "still identifies the client and keeps TLS locked down" do
      expect(storage.headers["User-Agent"]).to eq(config.user_agent)
      expect(storage.ssl.verify).to be(true)
      expect(storage.ssl.min_version).to eq(:TLS1_2)
    end

    # A UPO is XML; a JSON response middleware would try to parse it, and any re-encoding
    # risks the bytes no longer matching what the Ministry signed.
    it "does not parse the body as JSON" do
      stub_request(:get, link).to_return(status: 200, body: xml,
                                         headers: { "Content-Type" => "application/json" })

      expect(upo.download(link).xml).to be_a(String)
    end

    it "still raises on an error response from storage" do
      stub_request(:get, link).to_return(status: 403, body: "<Error>expired</Error>")

      expect { upo.download(link) }.to raise_error(Ksef::AuthorizationError)
    end
  end
end
