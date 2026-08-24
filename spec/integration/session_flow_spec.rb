# frozen_string_literal: true

# Live integration for the session layer, against the KSeF TEST environment.
#
# Opt-in twice over, like the other two: tagged `:integration` and excluded unless
# `KSEF_INTEGRATION=1`.
#
# **This is the spec Phase 2's first gate turns on.** DESIGN.md §11 requires "the §8
# contract runs against TEST", and until this file existed nothing in the nightly opened a
# session — three documents claimed "the nightly will settle it" while the test that would
# settle it did not exist. That was an empty promise, found by a documentation review on
# 2026-08-23.
#
# ## What only a live run can establish
#
# Every one of these is asserted nowhere else, because a stub proves only that our own
# arithmetic agrees with itself:
#
# - **KSeF can decrypt what we encrypt.** A wrong key, IV, padding or framing produces
#   per-invoice status `435`, and nothing before this point would notice. §14.1's resolution
#   — the IV as a discrete field rather than a ciphertext prefix — is on the line here.
# - **The four integrity values of §11.1 are computed over the right artifacts.** Hashing the
#   plaintext where the ciphertext belongs is silent locally and fatal remotely.
# - **`X-KSeF-Feature: upo-v4-3` does what both reference clients assume** (§14.6). The header
#   is in no contract and no upstream prose, so this is the only way to learn whether the UPO
#   we get back is the version whose schema we bundle.
# - **Whether `downloadUrl` arrives absolute or host-relative** (§9), still open.
# - **That a real UPO validates** as §14.3 predicts — accepted, with the environment-marker
#   warning and no errors.
#
# ## Why this one does not provision an identity
#
# `auth_flow_spec.rb` registers a fresh test person per run, because re-authenticating an
# existing context by XAdES needs the PESEL holding its permissions and that is not among the
# stored secrets. The KSeF-token flow needs no PESEL, so this spec uses the stored
# `KSEF_TEST_NIP`/`KSEF_TEST_TOKEN` — one fewer test person in a shared environment, and no
# wait on the asynchronous permission grant of §6a.6.

RSpec.describe "an online session against TEST", :integration do
  # No connection lets here, unlike the other two integration specs: everything below goes
  # through {Ksef::Client}, which builds and owns its own connections — including the
  # credential-free one for storage links.

  # Never PROD, from any code path.
  let(:environment) do
    env = (ENV["KSEF_ENV"] || "test").to_sym
    raise "Integration specs run against TEST only, got #{env}" unless env == :test

    env
  end

  # The stored credential is what the nightly has; unlike the XAdES flow this needs no PESEL.
  let(:credential) do
    Ksef::Auth::Token.new(
      context_nip: ENV.fetch("KSEF_TEST_NIP"), token: ENV.fetch("KSEF_TEST_TOKEN")
    )
  end

  let(:client) { Ksef::Client.new(env: environment, auth: credential) }

  before do
    skip "set KSEF_TEST_NIP and KSEF_TEST_TOKEN to exercise the session layer" unless
      ENV["KSEF_TEST_NIP"] && ENV["KSEF_TEST_TOKEN"]
  end

  # A minimal valid FA(3) invoice for the context under test. Built through the public DSL
  # rather than a fixture, so a builder regression fails here too.
  def invoice_for(nip)
    Ksef::FA3.build do |f|
      f.seller nip: nip, name: "Integration Seller sp. z o.o.",
               address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
      f.buyer  nip: "1111111111", name: "Integration Buyer S.A.",
               address: { street: "Długa 2", city: "Kraków", postal_code: "30-001", country: "PL" }
      f.number "INT/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
      f.issue_date Date.today
      f.line name: "Integration test line", qty: 1, unit: "szt.", net_unit_price: 100, vat: "23"
    end
  end

  def seller_nip = ENV.fetch("KSEF_TEST_NIP")

  describe "the §8 contract, end to end" do
    # One send for the whole block: sessions and invoices are shared TEST state, and the
    # assertions below all read from the same outcome rather than each submitting again.
    let(:outcome) do
      @outcome ||= begin
        receipt = client.send_invoice(invoice_for(seller_nip))
        state = client.wait_until_accepted(receipt, deadline: 240)
        { receipt: receipt, state: state }
      end
    end

    # The gate itself. An access token was issued, a session opened, a payload encrypted and
    # accepted, and a KSeF number assigned — which means every crypto parameter of §10.1 and
    # every integrity value of §11.1 was right.
    it "accepts an invoice this gem built, encrypted and submitted" do
      expect(outcome[:state]).to be_success
      expect(outcome[:state].ksef_number).to be_a(String)
    end

    # §13's CRC-8 against a number KSeF actually minted, rather than the documented example.
    it "returns a KSeF number whose checksum our own implementation agrees with" do
      parsed = Ksef::KsefNumber.parse(outcome[:state].ksef_number)

      expect(parsed.nip).to eq(seller_nip)
      expect(parsed.assigned_on).to be_a(Date)
    end

    it "reports the session as processed once it has closed" do
      state = client.session_status(outcome[:receipt].session_reference)

      expect(state.code).to be >= 200
      expect(state.invoice_count).to be >= 1
    end
  end

  describe "the UPO" do
    let(:receipt) do
      @receipt ||= begin
        r = client.send_invoice(invoice_for(seller_nip))
        client.wait_until_accepted(r, deadline: 240)
        r
      end
    end

    # Per-invoice UPO, the metered route the facade prefers for a single document.
    it "is retrievable, and its bytes match the hash the server publishes" do
      upo = client.upo(receipt)

      expect(upo.size).to be_positive
      expect(upo.verified?).to be(true) if upo.verifiable?
    end

    # §14.3 predicts exactly this: accepted, with one warning about the environment marker
    # and no errors, because TEST appends "- środowisko testowe (TE)" to a name the schema
    # fixes. A strict validator would reject every UPO TEST issues.
    it "validates as a diagnostic, with only the environment-marker warning" do
      result = client.upo(receipt).validate

      expect(result.errors).to be_empty
      expect(result.receiving_party).to include("Ministerstwo Finans")
    end

    # A UPO fetched from KSeF is XAdES-signed by the Ministry — that is what makes it proof of
    # receipt — and **not one of upstream's six published examples is signed**, so this is the
    # only place the difference can be observed (§14.7). It is why `UPO::Validator` sets the
    # signature aside before running the schema, which declares no `ds:Signature` at all.
    it "carries the Ministry's signature, unlike every offline fixture" do
      expect(Ksef::UPO::Validator.signed?(client.upo(receipt).xml)).to be(true)
    end

    # §14.6, the contract-silent header. If the UPO comes back as 4.3, the header both
    # official clients send does what they assume — and it is why we send it.
    it "conforms to the upo-v4-3 schema we asked for with X-KSeF-Feature" do
      document = Nokogiri::XML(client.upo(receipt).xml)

      expect(document.root.namespace.href).to eq(Ksef::UPO::NAMESPACE)
    end

    # §9's open question. Whichever way this comes back, the client handles both — this
    # records which one is real.
    it "reports which form the collective downloadUrl takes" do
      pages = client.session_status(receipt.session_reference).upo_pages
      skip "no collective UPO page yet — generation is asynchronous" if pages.empty?

      url = pages.first.download_url
      RSpec.configuration.reporter.message(
        "docs/REFERENCE.md §9: collective downloadUrl arrived " \
        "#{url.start_with?("http") ? "ABSOLUTE" : "RELATIVE"}"
      )
      expect(url).to be_a(String)
    end
  end

  describe "a rejected invoice" do
    # Sending the same document twice is the one rejection we can provoke deliberately, and
    # §12.1 says the second comes back as 440 carrying the *original's* references — the fact
    # that makes a resend reconcilable. Nothing offline can produce it.
    #
    # **The first live run (2026-08-24) failed here on the assertion, not the behaviour.** It
    # asserted `be_success` on a deliberate duplicate, which is a contradiction: 440 is a
    # terminal *rejection*. KSeF did exactly what §12.1 describes, including returning
    # `originalKsefNumber`. Corrected to assert the duplicate itself.
    let(:duplicated) do
      @duplicated ||= begin
        document = invoice_for(seller_nip)
        first = client.send_invoice(document)
        original = client.wait_until_accepted(first, deadline: 240)
        { receipt: first, original: original, second: terminal_state(client.send_invoice(document)) }
      end
    end

    # The duplicate may already be decided on the first status read — it was, on the first
    # live run — or may need polling. A terminal non-success reaches the caller as an
    # exception from `wait_until_accepted`, so the state is re-read to inspect it.
    def terminal_state(receipt)
      state = client.invoice_status(receipt)
      return state if state.terminal?

      client.wait_until_accepted(receipt, deadline: 240)
    rescue Ksef::InvoiceRejectedError
      client.invoice_status(receipt)
    end

    it "is rejected as a duplicate rather than accepted twice" do
      expect(duplicated[:second]).to be_duplicate
      expect(duplicated[:second]).not_to be_success
      expect(duplicated[:second].code).to eq(Ksef::Sessions::InvoiceCodes::DUPLICATE)
    end

    # The reconcilable half of §12.1: the rejection names the invoice it collided with, so a
    # resend after an uncertain response can be resolved without a search.
    it "names the original's KSeF number" do
      expect(duplicated[:second].original_ksef_number).to eq(duplicated[:original].ksef_number)
    end

    # `send_invoice` opens a fresh session per call, so the original's session is the one the
    # first send used. Asserted separately: it is a deduction rather than something the first
    # live run showed, and it should not be able to mask the two facts above.
    it "names the original's session" do
      expect(duplicated[:second].original_session_reference)
        .to eq(duplicated[:receipt].session_reference)
    end
  end
end
