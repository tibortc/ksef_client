# frozen_string_literal: true

require_relative "../support/crypto_fixtures"

RSpec.describe Ksef::Client do
  subject(:client) { described_class.new(env: :test, auth: credential) }

  let(:credential) { Ksef::Auth::Token.new(context_nip: "9999999999", token: "KSEF-TOKEN") }
  let(:session_ref) { "20260823-SO-1234567890-1234567890-AB" }
  let(:invoice_ref) { "20260823-FI-9999999999-9999999999-CD" }

  def base = "https://api-test.ksef.mf.gov.pl/v2"

  def json(body, status: 200)
    { status: status, body: JSON.dump(body), headers: { "Content-Type" => "application/json" } }
  end

  # The whole authentication prologue, plus the published keys it needs.
  def stub_authentication
    stub_public_keys
    stub_token_flow
  end

  def stub_public_keys
    stub_request(:get, "#{base}/security/public-key-certificates").to_return(
      json([CryptoFixtures.payload(usage: [Ksef::Crypto::Certificate::KSEF_TOKEN_ENCRYPTION]),
            CryptoFixtures.payload])
    )
  end

  def stub_token_flow
    stub_request(:post, "#{base}/auth/challenge").to_return(
      json({ "challenge" => "20250604-CR-461EA5B000-537A6BA15D-D7",
             "timestamp" => "2026-08-23T12:00:00Z", "timestampMs" => 1_787_824_800_000,
             "clientIp" => "203.0.113.7" })
    )
    stub_request(:post, "#{base}/auth/ksef-token").to_return(
      json({ "referenceNumber" => "20260823-AU-1-1-ZZ",
             "authenticationToken" => { "token" => "auth.jwt", "validUntil" => "2026-08-23T12:10:00Z" } },
           status: 202)
    )
    stub_request(:get, "#{base}/auth/20260823-AU-1-1-ZZ")
      .to_return(json({ "status" => { "code" => 200, "description" => "OK" } }))
    # Far-future expiries so AccessToken stays fresh for the length of a test. Using a
    # realistic fifteen minutes made it correctly judge itself stale against the wall clock
    # and reach for /auth/token/refresh — the proactive refresh working exactly as intended,
    # and a reminder that these stubs sit next to a real clock.
    stub_request(:post, "#{base}/auth/token/redeem").to_return(
      json({ "accessToken" => { "token" => "access.jwt", "validUntil" => "2099-01-01T00:00:00Z" },
             "refreshToken" => { "token" => "refresh.jwt", "validUntil" => "2099-01-02T00:00:00Z" } })
    )
  end

  def stub_session
    stub_request(:post, "#{base}/sessions/online").to_return(
      json({ "referenceNumber" => session_ref, "validUntil" => "2026-08-24T00:00:00Z" }, status: 201)
    )
    stub_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")
      .to_return(json({ "referenceNumber" => invoice_ref }, status: 202))
    stub_request(:post, "#{base}/sessions/online/#{session_ref}/close").to_return(status: 204)
  end

  def invoice_xml = "<Faktura>zażółć</Faktura>"

  describe "construction" do
    it "performs no I/O" do
      client

      expect(a_request(:any, /ksef.mf.gov.pl/)).not_to have_been_made
    end

    it "freezes its configuration, which is what makes sharing it safe" do
      expect(client.config).to be_frozen
    end

    it "redacts nothing interesting in #inspect, and names the environment" do
      expect(client.inspect).to eq("#<Ksef::Client env=:test>")
    end

    it "refuses to authenticate without a usable credential" do
      expect { described_class.new(env: :test, auth: "just a string").public_keys }
        .not_to raise_error
      expect { described_class.new(env: :test).credential }
        .to raise_error(Ksef::ConfigurationError, /needs auth:/)
    end

    it "accepts an already-redeemed access token and skips authentication" do
      tokens = Ksef::Auth::Tokens.from(
        "accessToken" => { "token" => "given.jwt", "validUntil" => "2099-01-01T00:00:00Z" },
        "refreshToken" => { "token" => "r", "validUntil" => "2099-01-01T00:00:00Z" }
      )
      existing = Ksef::Auth::AccessToken.new(tokens, client: instance_double(Ksef::Auth::Client))

      expect(described_class.new(env: :test, auth: existing).credential.bearer).to eq("given.jwt")
      expect(a_request(:post, "#{base}/auth/challenge")).not_to have_been_made
    end
  end

  describe "#send_invoice" do
    before do
      stub_authentication
      stub_session
    end

    it "authenticates, opens a session, submits, and closes — in that order" do
      receipt = client.send_invoice(invoice_xml)

      expect(receipt.session_reference).to eq(session_ref)
      expect(receipt.invoice_reference).to eq(invoice_ref)
      expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/close")).to have_been_made
    end

    # §11.2a, the decided default: a fresh session per call.
    it "opens a fresh session for each invoice" do
      2.times { client.send_invoice(invoice_xml) }

      expect(a_request(:post, "#{base}/sessions/online")).to have_been_made.twice
      expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/close")).to have_been_made.twice
    end

    it "authenticates only once across several sends" do
      2.times { client.send_invoice(invoice_xml) }

      expect(a_request(:post, "#{base}/auth/challenge")).to have_been_made.once
      expect(a_request(:post, "#{base}/auth/token/redeem")).to have_been_made.once
    end

    it "presents the redeemed access token, not the KSeF token" do
      client.send_invoice(invoice_xml)

      expect(a_request(:post, "#{base}/sessions/online")
        .with(headers: { "Authorization" => "Bearer access.jwt" })).to have_been_made
    end

    # The KSeF token is RSA-encrypted into the body, never sent as a bearer.
    it "never sends the KSeF token as a bearer" do
      client.send_invoice(invoice_xml)
      leaked = a_request(:any, /ksef.mf.gov.pl/).with do |request|
        request.headers["Authorization"].to_s.include?("KSEF-TOKEN")
      end

      expect(leaked).not_to have_been_made
    end

    it "closes the session even when submitting raises" do
      stub_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")
        .to_return(status: 400, body: JSON.dump("status" => 400, "title" => "nope"),
                   headers: { "Content-Type" => "application/problem+json" })

      expect { client.send_invoice(invoice_xml) }.to raise_error(Ksef::ApiError)
      expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/close")).to have_been_made
    end

    describe "validation" do
      it "validates a document that knows how to validate itself" do
        invoice = instance_double(Ksef::FA3::Invoice, to_xml: invoice_xml, validate!: true)
        client.send_invoice(invoice)

        expect(invoice).to have_received(:validate!)
      end

      it "can be turned off" do
        invoice = instance_double(Ksef::FA3::Invoice, to_xml: invoice_xml)
        client.send_invoice(invoice, validate: false)

        expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")).to have_been_made
      end

      # A raw String cannot validate itself, and refusing it would break §5's contract that
      # the transport layer accepts any XML.
      it "passes a raw XML String through" do
        expect { client.send_invoice(invoice_xml) }.not_to raise_error
      end

      # It is still bytes, and the admission rules of docs/REFERENCE.md §15.1 are about bytes.
      # Without this, the gem would ship the very document tier 1 exists to stop, as long as the
      # caller handed it over as a String — mis-encoded ERP text being precisely §15.1's case.
      it "still applies the byte-level rules to a raw String" do
        poisoned = invoice_xml.sub("</Faktura>", "#{0x87.chr(Encoding::UTF_8)}</Faktura>")

        expect { client.send_invoice(poisoned) }
          .to raise_error(Ksef::ValidationError, /U\+0087/)
        expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")).not_to have_been_made
      end

      # Not the schema tier, though: the transport layer is meant to carry documents this gem
      # does not model, and validating a caller's own XML against FA(3) would refuse them.
      it "does not hold a raw String to the FA(3) schema" do
        expect { client.send_invoice("<Cokolwiek>nie faktura</Cokolwiek>") }.not_to raise_error
      end

      # §5's contract is "anything with #to_xml, or a String". Something that is neither
      # validatable nor a String has no bytes to check until the session layer asks for them.
      it "leaves a document that is neither validatable nor a String alone" do
        document = Object.new
        def document.to_xml = "<Faktura/>"

        expect { client.send_invoice(document) }.not_to raise_error
      end

      it "surfaces a validation failure before opening a session" do
        invoice = instance_double(Ksef::FA3::Invoice)
        allow(invoice).to receive(:validate!).and_raise(Ksef::ValidationError, "bad")

        expect { client.session { |b| b.send_invoice(invoice) } }.to raise_error(Ksef::ValidationError)
        expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")).not_to have_been_made
      end
    end
  end

  describe "#session" do
    before do
      stub_authentication
      stub_session
    end

    it "opens one session for many invoices" do
      receipts = client.session { |batch| Array.new(3) { batch.send_invoice(invoice_xml) } }

      expect(receipts.size).to eq(3)
      expect(a_request(:post, "#{base}/sessions/online")).to have_been_made.once
      expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")).to have_been_made.times(3)
    end

    it "closes the session when the block ends" do
      client.session { |batch| batch.send_invoice(invoice_xml) }

      expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/close")).to have_been_made.once
    end

    # Closing is what starts UPO generation, so it has to happen on the error path too.
    it "closes the session when the block raises" do
      expect { client.session { raise "boom" } }.to raise_error("boom")
      expect(a_request(:post, "#{base}/sessions/online/#{session_ref}/close")).to have_been_made
    end

    it "keeps every receipt, since the collective UPO covers exactly those invoices" do
      batch_receipts = client.session do |batch|
        2.times { batch.send_invoice(invoice_xml) }
        batch.receipts
      end

      expect(batch_receipts.map(&:invoice_reference)).to eq([invoice_ref, invoice_ref])
    end

    it "exposes the open session and its reference" do
      reference = client.session(&:reference_number)

      expect(reference).to eq(session_ref)
    end

    # Nothing to close if opening never succeeded, and attempting it would replace the real
    # error with a confusing one about a session that does not exist.
    it "attempts no close when the session could not be opened" do
      stub_request(:post, "#{base}/sessions/online")
        .to_return(status: 403, body: JSON.dump("status" => 403, "reasonCode" => "missing-permissions"),
                   headers: { "Content-Type" => "application/problem+json" })

      expect { client.session { |b| b.send_invoice(invoice_xml) } }
        .to raise_error(Ksef::AuthorizationError)
      expect(a_request(:post, %r{/sessions/online/.*/close})).not_to have_been_made
    end

    it "stringifies the handle to the session reference" do
      expect(client.session(&:to_s)).to eq(session_ref)
    end

    it "accepts a different form code" do
      client.session(form_code: :fa2) { |batch| batch.send_invoice(invoice_xml) }
      matcher = a_request(:post, "#{base}/sessions/online").with do |request|
        JSON.parse(request.body).dig("formCode", "systemCode") == "FA (2)"
      end

      expect(matcher).to have_been_made
    end
  end

  describe "status and UPO" do
    let(:receipt) do
      Ksef::Client::Receipt.new(session_reference: session_ref, invoice_reference: invoice_ref,
                                session_valid_until: nil)
    end

    before { stub_authentication }

    it "waits until an invoice is accepted and reports its KSeF number" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}").to_return(
        json({ "status" => { "code" => 150, "description" => "Trwa" }, "referenceNumber" => invoice_ref }),
        json({ "status" => { "code" => 200, "description" => "OK" }, "referenceNumber" => invoice_ref,
               "ksefNumber" => "5265877635-20250826-0100001AF629-AF" })
      )
      state = client.wait_until_accepted(receipt, sleeper: ->(_) {})

      expect(state.ksef_number).to eq("5265877635-20250826-0100001AF629-AF")
    end

    it "reports a single status without waiting" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}")
        .to_return(json({ "status" => { "code" => 150 }, "referenceNumber" => invoice_ref }))

      expect(client.invoice_status(receipt)).to be_in_progress
    end

    # The per-invoice route is one metered request; chasing the unmetered link would cost a
    # metered status call first, so for a single invoice it is the cheaper of the two.
    it "fetches a per-invoice UPO by the direct route" do
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}/upo")
        .to_return(status: 200, body: "<Potwierdzenie/>")

      expect(client.upo(receipt).xml).to eq("<Potwierdzenie/>")
    end

    it "reports session status" do
      stub_request(:get, "#{base}/sessions/#{session_ref}")
        .to_return(json({ "status" => { "code" => 170 } }))

      expect(client.session_status(session_ref)).to be_closed
    end

    describe "#collective_upo" do
      it "follows every page, since one page is at most 10 000 invoices" do
        stub_request(:get, "#{base}/sessions/#{session_ref}").to_return(
          json({ "status" => { "code" => 200 }, "upo" => { "pages" => [
                 { "referenceNumber" => "P1", "downloadUrl" => "https://blob/1" },
                 { "referenceNumber" => "P2", "downloadUrl" => "https://blob/2" }
               ] } })
        )
        stub_request(:get, "https://blob/1").to_return(status: 200, body: "<One/>")
        stub_request(:get, "https://blob/2").to_return(status: 200, body: "<Two/>")

        expect(client.collective_upo(session_ref).map(&:xml)).to eq(["<One/>", "<Two/>"])
      end

      it "sends no credential to the storage links" do
        stub_request(:get, "#{base}/sessions/#{session_ref}").to_return(
          json({ "status" => { "code" => 200 },
                 "upo" => { "pages" => [{ "referenceNumber" => "P1", "downloadUrl" => "https://blob/1" }] } })
        )
        stub_request(:get, "https://blob/1").to_return(status: 200, body: "<One/>")
        client.collective_upo(session_ref)
        matcher = a_request(:get, "https://blob/1").with { |r| !r.headers.key?("Authorization") }

        expect(matcher).to have_been_made
      end

      it "is empty before the session has produced one" do
        stub_request(:get, "#{base}/sessions/#{session_ref}").to_return(json({ "status" => { "code" => 100 } }))

        expect(client.collective_upo(session_ref)).to be_empty
      end
    end
  end

  describe "#download_invoice" do
    before { stub_authentication }

    it "returns the invoice XML verbatim" do
      number = "5265877635-20250826-0100001AF629-AF"
      stub_request(:get, "#{base}/invoices/ksef/#{number}")
        .to_return(status: 200, body: "<Faktura>original</Faktura>")

      expect(client.download_invoice(number)).to eq("<Faktura>original</Faktura>")
    end

    it "checks the number's checksum before spending a request" do
      expect { client.download_invoice("5265877635-20250826-0100001AF629-00") }
        .to raise_error(Ksef::ValidationError, /checksum/)
      expect(a_request(:get, %r{/invoices/ksef/})).not_to have_been_made
    end
  end

  # docs/REFERENCE.md §10.2's documented recovery, which had no callers until 2026-08-23:
  # certificates are cached for an hour, so an emergency rotation inside that window makes the
  # cached publicKeyId unknown and the open fails 21470. Not a forbidden POST retry — a 21470
  # means the request was declined outright, so there is no session to duplicate.
  describe "key rotation during the cache window" do
    before { stub_authentication }

    def unknown_key_body
      JSON.dump("status" => 400, "title" => "Bad Request",
                "errors" => [{ "code" => 21_470, "description" => "Klucz nieznany" }])
    end

    it "re-fetches the certificate list and opens again on a 21470" do
      stub_request(:post, "#{base}/sessions/online").to_return(
        { status: 400, body: unknown_key_body, headers: { "Content-Type" => "application/problem+json" } },
        json({ "referenceNumber" => session_ref, "validUntil" => "2026-08-24T00:00:00Z" }, status: 201)
      )
      stub_request(:post, "#{base}/sessions/online/#{session_ref}/invoices")
        .to_return(json({ "referenceNumber" => invoice_ref }, status: 202))
      stub_request(:post, "#{base}/sessions/online/#{session_ref}/close").to_return(status: 204)

      expect(client.send_invoice(invoice_xml).invoice_reference).to eq(invoice_ref)
      expect(a_request(:get, "#{base}/security/public-key-certificates")).to have_been_made.twice
    end

    it "surfaces any other 400 without re-fetching" do
      stub_request(:post, "#{base}/sessions/online").to_return(
        status: 400, body: JSON.dump("status" => 400, "errors" => [{ "code" => 21_405 }]),
        headers: { "Content-Type" => "application/problem+json" }
      )

      expect { client.send_invoice(invoice_xml) }.to raise_error(Ksef::ApiError)
      expect(a_request(:get, "#{base}/security/public-key-certificates")).to have_been_made.once
    end
  end

  describe "thread safety" do
    before do
      stub_authentication
      stub_session
    end

    # DESIGN.md §5.2. The client holds no session, so concurrent sends cannot interleave in
    # one — and authentication happens once because the check is inside the mutex.
    it "authenticates once across concurrent sends, each in its own session" do
      receipts = Array.new(6) { Thread.new { client.send_invoice(invoice_xml) } }.map(&:value)

      expect(receipts.map(&:invoice_reference).uniq).to eq([invoice_ref])
      expect(a_request(:post, "#{base}/auth/challenge")).to have_been_made.once
      expect(a_request(:post, "#{base}/sessions/online")).to have_been_made.times(6)
    end
  end

  # The point of the whole exercise: DESIGN.md §8's snippet, run as written.
  describe "the DESIGN.md §8 contract" do
    before do
      stub_authentication
      stub_session
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}").to_return(
        json({ "status" => { "code" => 200, "description" => "OK" }, "referenceNumber" => invoice_ref,
               "ksefNumber" => "9999999999-20260823-0100001AF629-3F" })
      )
      stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}/upo")
        .to_return(status: 200, body: "<Potwierdzenie>signed</Potwierdzenie>")
    end

    it "runs verbatim, from build to UPO" do
      invoice = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "ACME sp. z o.o.",
                 address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
        f.buyer  nip: "1111111111", name: "Klient S.A.",
                 address: { street: "Długa 2", city: "Kraków", postal_code: "30-001", country: "PL" }
        f.number "FV/2026/08/001"
        f.issue_date Date.new(2026, 8, 23)
        f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23"
      end

      result = client.send_invoice(invoice)
      status = client.wait_until_accepted(result.reference)
      upo = client.upo(result.reference)

      expect(status.ksef_number).to eq("9999999999-20260823-0100001AF629-3F")
      expect(upo.xml).to eq("<Potwierdzenie>signed</Potwierdzenie>")
    end

    # §8 writes `client.wait_until_accepted(result.reference)`, and this is why that works.
    it "makes result.reference sufficient to look the invoice up" do
      result = client.send_invoice(invoice_xml)

      expect(result.reference).to equal(result)
      expect(result.reference.to_s).to eq(invoice_ref)
    end

    # A session closes itself twelve hours in (§11), after which the collective UPO is
    # generated — worth being able to check on a long batch rather than assuming.
    it "reports when the session that carried the invoice has expired" do
      result = client.send_invoice(invoice_xml)

      expect(result.session_valid_until).to eq(Time.utc(2026, 8, 24))
      expect(result.session_expired?(Time.utc(2026, 8, 23, 23, 59))).to be(false)
      expect(result.session_expired?(Time.utc(2026, 8, 24, 0, 1))).to be(true)
    end

    it "never claims expiry when the server sent no validUntil" do
      receipt = Ksef::Client::Receipt.new(session_reference: "S", invoice_reference: "I",
                                          session_valid_until: nil)

      expect(receipt).not_to be_session_expired
    end
  end
end
