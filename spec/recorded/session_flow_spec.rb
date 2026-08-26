# frozen_string_literal: true

require "spec_helper"

# The session flow, replayed against responses KSeF actually sent (DESIGN.md §9.1).
#
# **Excluded until a cassette exists** — `spec/support/vcr.rb` filters `:recorded` out when
# `spec/cassettes/` is empty, and `spec/recorded_tier_spec.rb` asserts that state so the
# absence is visible rather than silent. Record with `rake vcr:record`, which needs TEST
# credentials and refuses production.
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
# ## Determinism
#
# The recording's request bodies carry a randomly-generated AES key encrypted with randomised
# RSA-OAEP padding, so they can never be reproduced (§9.1, obstacle 1). Two consequences: the
# matcher ignores the body, and the replay injects the *same* encryptor the recording used —
# which is what `Ksef::Client#session(encryptor:)` exists for.
RSpec.describe "the session flow, recorded", :recorded, vcr: { cassette_name: "session_flow" } do
  # The key and IV the recording used. Fixed values rather than a fresh pair: `Encryptor.new`
  # is public beside `.generate` exactly so a replay can supply them.
  let(:encryptor) do
    Ksef::Crypto::Encryptor.new(key: ["00" * 32].pack("H*"), iv: ["00" * 16].pack("H*"))
  end

  # Scrubbed out of the cassette, so the replay supplies its own placeholder. The value is
  # never compared — the matcher is method + URI.
  let(:credential) { Ksef::Auth::Token.new(context_nip: "0000000000", token: "<KSEF_TEST_TOKEN>") }
  let(:client) { Ksef::Client.new(env: :test, auth: credential) }

  def invoice
    Ksef::FA3.build do |f|
      f.seller nip: "0000000000", name: "Recorded Seller sp. z o.o.",
               address: { street: "ul. Testowa 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
      f.buyer nip: "1111111111", name: "Recorded Buyer S.A.",
              address: { street: "ul. Inna 2", city: "Kraków", postal_code: "30-001", country: "PL" }
      f.number "FV/RECORDED/001"
      f.issue_date Date.new(2026, 8, 26)
      f.issued_at "2026-08-26T09:00:00Z"
      f.line name: "Consulting", qty: 1, unit: "szt.", net_unit_price: "100.00",
             net_amount: "100.00", vat: "23"
    end
  end

  it "sends an invoice and is given a KSeF number" do
    receipt = client.send_invoice(invoice, encryptor: encryptor)
    status = client.wait_until_accepted(receipt.reference)

    expect(status).to be_accepted
    expect(status.ksef_number).to be_a(String)
  end

  # §13: the checksum is ours and the number is theirs, so agreement is a real assertion.
  it "is given a KSeF number whose CRC-8 agrees with ours" do
    receipt = client.send_invoice(invoice, encryptor: encryptor)
    number = Ksef::KsefNumber.parse(client.wait_until_accepted(receipt.reference).ksef_number)

    expect(number).to be_checksum_verified
  end

  # §12.3: the UPO comes back over a credential-free connection to a different host, and its
  # bytes are kept verbatim because it is legal proof of receipt (§12.2).
  it "returns a UPO whose bytes match the hash the storage link declares" do
    receipt = client.send_invoice(invoice, encryptor: encryptor)
    client.wait_until_accepted(receipt.reference)

    upo = client.upo(receipt.reference)

    expect(upo.xml).to include("upo-v4-3")
    expect(upo).to be_integrity_verified
  end
end
