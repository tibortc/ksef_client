# frozen_string_literal: true

RSpec.describe Ksef::Sessions::Status do
  subject(:status) { described_class.new(connection, "access.jwt") }

  let(:connection) { Ksef::HTTP::Connection.build(Ksef::Configuration.new(env: :test)) }
  let(:session_ref) { "20260823-SO-1234567890-1234567890-AB" }
  let(:invoice_ref) { "20260823-FI-9999999999-9999999999-CD" }

  def base = "https://api-test.ksef.mf.gov.pl/v2"

  def json(body, status: 200)
    { status: status, body: JSON.dump(body), headers: { "Content-Type" => "application/json" } }
  end

  def session_body(code, **rest)
    { "status" => { "code" => code, "description" => "d" },
      "dateCreated" => "2026-08-23T12:00:00Z",
      "dateUpdated" => "2026-08-23T12:05:00Z" }.merge(rest)
  end

  def invoice_body(code, **rest)
    { "status" => { "code" => code, "description" => "d" },
      "referenceNumber" => invoice_ref }.merge(rest)
  end

  def stub_session(*bodies)
    stub_request(:get, "#{base}/sessions/#{session_ref}").to_return(*bodies.map { |b| json(b) })
  end

  def stub_invoice(*bodies)
    stub_request(:get, "#{base}/sessions/#{session_ref}/invoices/#{invoice_ref}")
      .to_return(*bodies.map { |b| json(b) })
  end

  # Never actually sleep, and let the clock be driven where a deadline is under test.
  def quiet = { sleeper: ->(_) {} }

  describe "#session" do
    it "parses the status, counts and timestamps" do
      stub_session(session_body(200, "invoiceCount" => 3, "successfulInvoiceCount" => 2,
                                     "failedInvoiceCount" => 1, "validUntil" => "2026-08-24T00:00:00Z"))
      state = status.session(session_ref)

      expect(state.code).to eq(200)
      expect([state.invoice_count, state.successful_count, state.failed_count]).to eq([3, 2, 1])
      expect(state.created_at).to eq(Time.utc(2026, 8, 23, 12))
      expect(state.valid_until).to eq(Time.utc(2026, 8, 24))
    end

    # §12 — a collective UPO holds at most 10 000 entries, so pages is an array and reading
    # only the first loses proof of receipt for the rest.
    it "keeps every UPO page, not just the first" do
      stub_session(session_body(200, "upo" => { "pages" => [
                                  { "referenceNumber" => "P1", "downloadUrl" => "https://blob/1",
                                    "downloadUrlExpirationDate" => "2026-08-23T13:00:00Z" },
                                  { "referenceNumber" => "P2", "downloadUrl" => "https://blob/2" }
                                ] }))
      pages = status.session(session_ref).upo_pages

      expect(pages.map(&:reference_number)).to eq(%w[P1 P2])
      expect(pages.first.expires_at).to eq(Time.utc(2026, 8, 23, 13))
      expect(pages.first.download_url).to eq("https://blob/1")
    end

    it "stringifies to its reference number" do
      stub_session(session_body(200))

      expect(status.session(session_ref).to_s).to eq(session_ref)
    end

    it "has no UPO pages before the session is closed" do
      stub_session(session_body(100))

      expect(status.session(session_ref).upo_pages).to be_empty
    end

    it "presents the access token" do
      stub_session(session_body(100))
      status.session(session_ref)

      expect(a_request(:get, "#{base}/sessions/#{session_ref}")
        .with(headers: { "Authorization" => "Bearer access.jwt" })).to have_been_made
    end

    # 415 at session level is the RSA-OAEP key wrap failing, distinct from a per-invoice 435.
    it "distinguishes a rejected symmetric key" do
      stub_session(session_body(415))
      state = status.session(session_ref)

      expect(state.key_rejected?).to be(true)
      expect(state.terminal?).to be(true)
    end

    # Closing starts asynchronous UPO generation, so 170 is not the end.
    it "treats a closed session as still in progress, because the UPO is not ready" do
      stub_session(session_body(170))
      state = status.session(session_ref)

      expect(state.closed?).to be(true)
      expect(state.in_progress?).to be(true)
      expect(state.success?).to be(false)
    end

    it "falls back to our own wording when the server sends none" do
      stub_session({ "status" => { "code" => 445 } })

      expect(status.session(session_ref).explain).to include("no valid invoices")
    end

    it "prefers KSeF's own wording when there is some" do
      stub_session({ "status" => { "code" => 445, "description" => "Brak poprawnych faktur" } })

      expect(status.session(session_ref).explain).to eq("Brak poprawnych faktur")
    end
  end

  describe "#invoice" do
    it "parses the KSeF number and acquisition date on success" do
      stub_invoice(invoice_body(200, "ksefNumber" => "5265877635-20250826-0100001AF629-AF",
                                     "invoiceNumber" => "FV/2026/08/001",
                                     "acquisitionDate" => "2026-08-23T12:04:00Z"))
      state = status.invoice(session_ref, invoice_ref)

      expect(state.success?).to be(true)
      expect(state.ksef_number).to eq("5265877635-20250826-0100001AF629-AF")
      expect(state.acquisition_date).to eq(Time.utc(2026, 8, 23, 12, 4))
    end

    # The per-invoice UPO link arrives here rather than needing its own call.
    it "surfaces the per-invoice UPO link and its expiry" do
      stub_invoice(invoice_body(200, "upoDownloadUrl" => "https://blob/upo",
                                     "upoDownloadUrlExpirationDate" => "2026-08-23T13:00:00Z"))
      state = status.invoice(session_ref, invoice_ref)

      expect(state.upo_download_url).to eq("https://blob/upo")
      expect(state.upo_download_url_expires_at).to eq(Time.utc(2026, 8, 23, 13))
    end

    # 100 is "accepted for further processing" — undecided, and with no KSeF number yet.
    # The reference clients stop here; we do not.
    it "treats 100 as still in progress, not as a result" do
      stub_invoice(invoice_body(100))
      state = status.invoice(session_ref, invoice_ref)

      expect(state.in_progress?).to be(true)
      expect(state.terminal?).to be(false)
      expect(state.ksef_number).to be_nil
    end

    it "treats 150 as in progress too" do
      stub_invoice(invoice_body(150))

      expect(status.invoice(session_ref, invoice_ref).in_progress?).to be(true)
    end

    it "carries the original's references on a duplicate" do
      stub_invoice(invoice_body(440, "status" => {
                                  "code" => 440, "description" => "Duplikat faktury",
                                  "extensions" => {
                                    "originalKsefNumber" => "5265877635-20250826-0100001AF629-AF",
                                    "originalSessionReferenceNumber" => "20260820-SO-1-1-ZZ"
                                  }
                                }))
      state = status.invoice(session_ref, invoice_ref)

      expect(state.duplicate?).to be(true)
      expect(state.original_ksef_number).to eq("5265877635-20250826-0100001AF629-AF")
      expect(state.original_session_reference).to eq("20260820-SO-1-1-ZZ")
    end

    it "has empty extensions for every other status" do
      stub_invoice(invoice_body(430))
      state = status.invoice(session_ref, invoice_ref)

      expect(state.extensions).to eq({})
      expect(state.original_ksef_number).to be_nil
    end

    # 550 is the system interrupting itself; a duplicate is emphatically not retryable.
    it "marks only the system cancellation as retryable" do
      stub_invoice(invoice_body(550), invoice_body(440))

      expect(status.invoice(session_ref, invoice_ref).retryable?).to be(true)
      expect(status.invoice(session_ref, invoice_ref).retryable?).to be(false)
    end

    it "falls back to our own wording when the server sends none" do
      stub_invoice({ "status" => { "code" => 435 }, "referenceNumber" => invoice_ref })

      expect(status.invoice(session_ref, invoice_ref).explain)
        .to include("could not decrypt the file")
    end

    it "stringifies to its reference number" do
      stub_invoice(invoice_body(200))

      expect(status.invoice(session_ref, invoice_ref).to_s).to eq(invoice_ref)
    end

    # The number is parsed rather than handed back raw, so its CRC-8 is checked and the
    # acceptance date is a Date.
    it "parses the KSeF number it returns, checksum and all" do
      stub_invoice(invoice_body(200, "ksefNumber" => "5265877635-20250826-0100001AF629-AF"),
                   invoice_body(150))
      parsed = status.invoice(session_ref, invoice_ref).ksef_number_parsed

      expect(parsed.assigned_on).to eq(Date.new(2025, 8, 26))
      expect(status.invoice(session_ref, invoice_ref).ksef_number_parsed).to be_nil
    end
  end

  describe "#wait_for_invoice" do
    it "polls while in progress and stops at the first terminal status" do
      stub_invoice(invoice_body(100), invoice_body(150), invoice_body(200))
      slept = []
      state = status.wait_for_invoice(session_ref, invoice_ref, sleeper: ->(s) { slept << s })

      expect(state.success?).to be(true)
      expect(slept).to eq([1, 2])
    end

    it "backs off exponentially and caps the interval" do
      stub_invoice(*Array.new(8) { invoice_body(150) }, invoice_body(200))
      slept = []
      status.wait_for_invoice(session_ref, invoice_ref, sleeper: ->(s) { slept << s }, deadline: 10_000)

      expect(slept).to eq([1, 2, 4, 8, 16, 30, 30, 30])
    end

    it "does not sleep when the first poll is already terminal" do
      stub_invoice(invoice_body(200))
      slept = []
      status.wait_for_invoice(session_ref, invoice_ref, sleeper: ->(s) { slept << s })

      expect(slept).to be_empty
    end

    it "yields each poll so a caller can report progress" do
      stub_invoice(invoice_body(150), invoice_body(200))
      seen = []
      status.wait_for_invoice(session_ref, invoice_ref, **quiet) { |s| seen << s.code }

      expect(seen).to eq([150, 200])
    end

    # The operation has not failed, it has outlasted the wait — the message says so, because
    # the two call for different responses.
    it "raises a TimeoutError that distinguishes slow from failed" do
      stub_invoice(invoice_body(150))

      expect { status.wait_for_invoice(session_ref, invoice_ref, deadline: 3, **quiet) }
        .to raise_error(Ksef::TimeoutError, /still 150.*has not failed, only outlasted/m)
    end
  end

  describe "#wait_until_accepted" do
    it "returns the state when the invoice is accepted" do
      stub_invoice(invoice_body(150), invoice_body(200, "ksefNumber" => "N"))

      expect(status.wait_until_accepted(session_ref, invoice_ref, **quiet).ksef_number).to eq("N")
    end

    it "raises with KSeF's own wording and details" do
      stub_invoice({ "status" => { "code" => 450, "description" => "Błąd semantyki",
                                   "details" => ["P_15 nie zgadza się"] },
                     "referenceNumber" => invoice_ref })

      expect { status.wait_until_accepted(session_ref, invoice_ref, **quiet) }
        .to raise_error(Ksef::InvoiceRejectedError, /status 450, Błąd semantyki \(P_15 nie zgadza się\)/)
    end

    it "names the original submission when the rejection was a duplicate" do
      stub_invoice({ "status" => { "code" => 440, "description" => "Duplikat",
                                   "extensions" => { "originalKsefNumber" => "ORIG",
                                                     "originalSessionReferenceNumber" => "SESS" } },
                     "referenceNumber" => invoice_ref })

      expect { status.wait_until_accepted(session_ref, invoice_ref, **quiet) }
        .to raise_error(Ksef::InvoiceRejectedError, /The original is ORIG in session SESS/)
    end

    it "omits the detail clause when there are none" do
      stub_invoice(invoice_body(430))

      expect { status.wait_until_accepted(session_ref, invoice_ref, **quiet) }
        .to raise_error(Ksef::InvoiceRejectedError, /status 430, d\z/)
    end
  end

  describe "#wait_for_session" do
    # Waits for 200, not 170: the collective UPO does not exist at "closed".
    it "keeps polling past the closed state until the session is processed" do
      stub_session(session_body(170), session_body(170), session_body(200))
      seen = []
      state = status.wait_for_session(session_ref, **quiet) { |s| seen << s.code }

      expect(seen).to eq([170, 170, 200])
      expect(state.success?).to be(true)
    end

    it "stops at a terminal failure" do
      stub_session(session_body(445))

      expect(status.wait_for_session(session_ref, **quiet).success?).to be(false)
    end
  end

  describe "the endpoints it deliberately does not offer" do
    # GET /sessions is 10 req/min — the tightest budget in the API. Not exposing a list call
    # is the simplest way to keep a poller off it.
    it "has no method that would poll the session list" do
      expect(status).not_to respond_to(:sessions, :list)
    end
  end

  it "asks an AccessToken for a bearer per request, so a refresh is picked up mid-poll" do
    credential = instance_double(Ksef::Auth::AccessToken)
    allow(credential).to receive(:bearer).and_return("first.jwt", "second.jwt")
    stub_session(session_body(150), session_body(200))
    described_class.new(connection, credential).wait_for_session(session_ref, **quiet)

    expect(a_request(:get, "#{base}/sessions/#{session_ref}")
      .with(headers: { "Authorization" => "Bearer second.jwt" })).to have_been_made
  end

  it "refuses a reference number that could alter the request path" do
    expect { status.session("../../auth/sessions/current") }
      .to raise_error(Ksef::ValidationError, /not of the documented form/)
    expect { status.invoice(session_ref, "../failed") }
      .to raise_error(Ksef::ValidationError, /not of the documented form/)
  end
end
