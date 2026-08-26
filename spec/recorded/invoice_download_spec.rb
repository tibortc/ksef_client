# frozen_string_literal: true

require "spec_helper"

# The two retrieval paths the other cassettes never touch (DESIGN.md §9.1).
#
# ## What was missing, and why it was not obvious
#
# All 31 interactions in the first three cassettes are on `api-test.ksef.mf.gov.pl`, and none is
# on `/invoices/ksef/`. So two things were carried, documented and WebMock-verified without ever
# having run:
#
#   1. **`Invoices::Client#download`** — `GET /invoices/ksef/{ksefNumber}`, the only way to get
#      an invoice back out of KSeF once it has been accepted.
#   2. **The whole storage leg** — `HTTP::Connection.storage`, the pre-signed `downloadUrl`, and
#      `x-ms-meta-hash` verification *on that route*. §9.1's obstacle 5 asserted this request
#      "is part of the cassette too", which was never true: `Client#upo` deliberately uses the
#      metered per-invoice route (§11.2a), so the unmetered link is only reached by
#      `#collective_upo`, and nothing recorded one.
#
# The `uri_without_param` matcher in `spec/support/vcr.rb` existed the whole time for a request
# the tier never made.
#
# ## One invoice, both paths
#
# A collective UPO needs a closed, fully-processed session, and downloading an invoice needs one
# KSeF has accepted — so both need an invoice to exist. They share one here rather than costing
# two: **this example creates one permanent TEST invoice per recording**, the same price as each
# example in `session_flow_spec.rb`.
RSpec.describe "invoice retrieval, recorded", :recorded, :vcr do
  include_context "with a recorded KSeF flow"

  let(:encryptor) do
    Ksef::Crypto::Encryptor.new(key: ["33" * 32].pack("H*"), iv: ["44" * 16].pack("H*"))
  end

  def invoice
    Ksef::FA3.build do |f|
      f.number "FV/REC/DL/#{Time.now.strftime("%Y%m%d%H%M%S")}"
      f.issue_date Date.today
      f.seller nip: context_nip, name: "Recorded Seller sp. z o.o.",
               address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
      f.buyer nip: "1111111111", name: "Recorded Buyer S.A.",
              address: { street: "Dluga 2", city: "Krakow", postal_code: "30-001", country: "PL" }
      f.line name: "Usluga rejestrowana", quantity: 1, net_unit_price: "100.00", vat_rate: "23"
    end
  end

  def wait_for(receipt)
    client.wait_until_accepted(receipt, **(recording? ? {} : { sleeper: sleeper }))
  end

  # `#collective_upo` needs the session *processed*, not merely closed — `170` means closed and
  # says nothing about the asynchronous UPO generation that follows (§12.1).
  def wait_for_session(reference)
    20.times do
      state = client.session_status(reference)
      return state if state.terminal?

      sleeper.call(2)
    end
    raise "session #{reference} never finished processing"
  end

  it "downloads an accepted invoice by its KSeF number, and follows the unmetered UPO link" do
    sent = invoice
    receipt = client.send_invoice(sent, encryptor: encryptor)
    accepted = wait_for(receipt)
    wait_for_session(receipt.session_reference)

    # 1. The metered per-invoice route this gem's facade prefers — already covered elsewhere,
    #    asserted here only so the KSeF number below is known good.
    expect(accepted).to be_success

    # 2. `GET /invoices/ksef/{ksefNumber}`. KSeF hands back the FA(3) document verbatim, so it
    #    must parse and carry the number we sent — this is the round trip through the service
    #    rather than through our own serializer.
    downloaded = client.download_invoice(accepted.ksef_number)

    expect(Ksef::FA3.parse(downloaded).number).to eq(sent.number)
    expect(Ksef::FA3::Validator.errors_for(downloaded)).to be_empty

    # 3. The storage leg. `#collective_upo` follows the pre-signed link, on a connection with no
    #    bearer and no base URL, and verifies `x-ms-meta-hash` over the bytes it gets back —
    #    `UPO::Document#verify!` raises `IntegrityError` if they disagree, so reaching this line
    #    is the assertion.
    pages = client.collective_upo(receipt.session_reference)

    expect(pages).not_to be_empty
    expect(pages.first).to have_attributes(source: :storage, xml: include("Potwierdzenie"))
  end
end
