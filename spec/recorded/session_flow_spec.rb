# frozen_string_literal: true

require "spec_helper"

# The session flow, replayed against responses KSeF actually sent (DESIGN.md §9.1).
#
# **Excluded until a cassette exists** — `spec/support/vcr.rb` filters `:recorded` out when
# `spec/cassettes/` is empty, and `spec/recorded_tier_spec.rb` asserts that state so the
# absence is visible rather than silent. Record by dispatching
# `.github/workflows/record-cassettes.yml`, which runs in the `ksef-test` environment because
# that is where the credentials are.
#
# ## What this proves that the other tiers do not
#
# `spec/ksef/client_spec.rb` drives the same flow against WebMock, so the *request shapes* are
# already covered. What a stub cannot give is a **real response body**: the exact `validUntil`
# format, the status-code sequence a real session walks through, the shape of a UPO page, the
# `x-ms-meta-hash` header on the storage link. Two of the four defects the first live run found
# were invisible to stubs precisely because the stubs encoded our own assumptions
# (`docs/REFERENCE.md` §14.7 — a real UPO is signed, and upstream's own schema declares no
# `ds:Signature`).
#
# And unlike the live tier, this runs per push, in milliseconds, with no credentials.
#
# ## Recording and replaying are not the same run
#
# The first version of this file hardcoded the *replay* placeholders and then tried to record
# with them. KSeF answered `[21405] Invalid NIP format`: `0000000000` passes this gem's
# checksum — only PROD checks the digits (§15.3) — and fails the schema's structural rule that
# the first digit is non-zero (§13). So every value that differs between the two modes is read
# from the environment, and the fallback exists only so a replay can construct.
# **One cassette per example, not one for the describe block.** The first version shared a
# single `session_flow` cassette across every example, and each example runs a *whole* flow —
# open a session, send, poll, close, fetch the UPO. Their interactions therefore interleaved in
# one file, and because every `POST /sessions/online` has the same URI, replay handed them out
# in recorded order: one example drifting by a single request left a later one asking for a UPO
# under session references that belonged to a different flow. VCR called it
# `UnhandledHTTPRequestError`, which is accurate and unhelpful.
#
# `vcr: true` with `configure_rspec_metadata!` names the cassette after the example, so each is
# self-contained, order-independent, and re-recordable on its own.
#
# The examples are grouped rather than split one-assertion-each for a reason that is not style:
# **each example is one real invoice in TEST**, permanent and unwithdrawable. Two examples cost
# two invoices per recording; four cost four.
RSpec.describe "the session flow, recorded", :recorded, :vcr do
  def recording? = ENV["KSEF_VCR_RECORD"] == "1"

  # The real context when recording; a format-valid stand-in when replaying. The stand-in is
  # never sent anywhere — requests are matched on method and URI — but `Subject` and
  # `Auth::Token` both validate what they are handed, so it has to be a plausible NIP.
  def context_nip = ENV.fetch("KSEF_TEST_NIP", "9999999999")

  # Scrubbed out of the cassette on write (`spec/support/vcr.rb`).
  def access_token = ENV.fetch("KSEF_TEST_TOKEN", "<KSEF_TEST_TOKEN>")

  let(:credential) { Ksef::Auth::Token.new(context_nip: context_nip, token: access_token) }
  let(:client) { Ksef::Client.new(env: :test, auth: credential) }

  # Fixed key and IV rather than a fresh pair: `Encryptor.new` is public beside `.generate`
  # exactly so a replay can supply the ones its recording used (§9.1, obstacle 1).
  let(:encryptor) do
    Ksef::Crypto::Encryptor.new(key: ["11" * 32].pack("H*"), iv: ["22" * 16].pack("H*"))
  end

  # Real waits while recording, none while replaying. `Sessions::Status#poll` takes an
  # injectable sleeper, so a replayed poll costs nothing.
  def wait_for(receipt)
    client.wait_until_accepted(receipt, **(recording? ? {} : { sleeper: ->(_seconds) {} }))
  end

  # **The seller must be the authenticated context** — KSeF refuses an invoice issued by anyone
  # else. And the number must be unique per recording: §15.2's duplicate key is NIP + number +
  # issue date, so a fixed number would make every re-recording a `440`. Replay does not care,
  # because request bodies are never matched.
  def invoice
    Ksef::FA3.build do |f|
      f.seller nip: context_nip, name: "Recorded Seller sp. z o.o.",
               address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
      f.buyer nip: "1111111111", name: "Recorded Buyer S.A.",
              address: { street: "Długa 2", city: "Kraków", postal_code: "30-001", country: "PL" }
      f.number "REC/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
      f.issue_date Date.today
      f.line name: "Recorded line", qty: 1, unit: "szt.", net_unit_price: 100, vat: "23"
    end
  end

  # One invoice, three facts that only a real response can establish: KSeF accepted what this
  # gem encrypted, it assigned a number, and our CRC-8 agrees with the one it chose (§13).
  it "sends an invoice, and the KSeF number it returns passes our own checksum" do
    status = wait_for(client.send_invoice(invoice, encryptor: encryptor))

    expect(status).to be_success
    expect(status.ksef_number).to be_a(String)
    expect(Ksef::KsefNumber.parse(status.ksef_number)).to be_checksum_verified
  end

  # A second invoice, for the UPO. §12.3: it arrives over a credential-free connection to a
  # different host, and its bytes are kept verbatim because it is legal proof of receipt.
  #
  # The signature assertion is the one this tier exists for. §14.7: a real UPO is XAdES-signed
  # while upstream's own UPO schema declares no `ds:Signature`, and none of the six published
  # examples is signed — so nothing offline could reveal it. The live run of 2026-08-24 found
  # it; this is what keeps it found.
  it "returns a signed UPO in the version whose schema this gem bundles" do
    receipt = client.send_invoice(invoice, encryptor: encryptor)
    wait_for(receipt)

    upo = client.upo(receipt)
    document = Nokogiri::XML(upo.xml)

    expect(document.root.name).to eq("Potwierdzenie")
    expect(document.root.namespace.href).to eq(Ksef::UPO::NAMESPACE)
    expect(document.xpath("//ds:Signature", "ds" => Ksef::UPO::Validator::SIGNATURE_NAMESPACE))
      .not_to be_empty
    expect(Ksef::UPO::Validator.validate(upo.xml)).to be_valid
  end
end
