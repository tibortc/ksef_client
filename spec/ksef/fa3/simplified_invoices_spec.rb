# frozen_string_literal: true

require "nokogiri"
require_relative "../../support/fa3_corpus"

# `UPR`, the simplified invoice of art. 106e ust. 5 pkt 3, and with it the mechanism it needs:
# **a row that states no amount at all** (docs/REFERENCE.md §8.6). The same shape appears on a
# collective correction's descriptive row, so this is not a `UPR`-only concession.
RSpec.describe "FA(3) rows that state no amount" do
  def seller
    Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME sp. z o.o.",
                           address: Ksef::FA3::Address.new(line1: "Prosta 1, 00-001 Warszawa"))
  end

  def buyer
    Ksef::FA3::Subject.new(nip: "1111111111", name: "Klient S.A.",
                           address: Ksef::FA3::Address.new(line1: "Długa 2, 30-001 Kraków"))
  end

  def named_only(**overrides) = Ksef::FA3::Line.new(name: "wiertarka Wiertex mk5", **overrides)

  def priced(**overrides)
    Ksef::FA3::Line.new(name: "Consulting", quantity: 1, unit: "szt.",
                        net_unit_price: "100", net_amount: "100", vat_rate: "23", **overrides)
  end

  def invoice(**overrides)
    Ksef::FA3::Invoice.new(
      seller: seller, buyer: buyer, number: "FV/2026/02/150",
      issue_date: Date.new(2026, 2, 15), issued_at: Time.utc(2026, 2, 15),
      invoice_type: "UPR", lines: [named_only],
      totals: Ksef::FA3::Totals.new(gross: "450",
                                    buckets: { "P_13_1" => "365.85", "P_14_1" => "84.15" }),
      **overrides
    )
  end

  describe Ksef::FA3::Line do
    it "needs only a name, every other element being minOccurs=0" do
      expect(named_only.to_fa3(row_number: 1)).to eq("NrWierszaFa" => 1, "P_7" => "wiertarka Wiertex mk5")
    end

    # nil is not zero: the row states nothing, rather than stating that it is worth nothing.
    # `#vat` used to be the one exception, answering a definite zero where the tax is simply
    # unknown — so `lines.sum(&:vat)` under-reported in silence while `sum(&:net)` raised.
    it "reports no amount rather than a zero one, tax included" do
      expect(named_only)
        .to have_attributes(net: nil, vat: nil, gross: nil, priced?: false, summarised?: false)
    end

    # The other absence is a different one: an exempt or reverse-charge row states a real
    # amount that carries no tax, and zero is the true answer there.
    it "still reports zero tax for a rate code that genuinely carries none" do
      expect(priced(vat_rate: "zw")).to have_attributes(net: BigDecimal("100"), vat: BigDecimal(0))
    end

    it "is still unsummarised with a rate but no amount, as Przykład 16's row is" do
      expect(named_only(vat_rate: "23")).to have_attributes(priced?: false, summarised?: false)
    end

    it "is unsummarised with an amount but no rate, which is the dangerous half" do
      expect(priced(vat_rate: nil)).to have_attributes(priced?: true, summarised?: false)
    end
  end

  describe "what a UPR writes" do
    it "is schema-valid, and its row carries a name and nothing else" do
      document = Nokogiri::XML(invoice.to_xml).remove_namespaces!

      expect(Ksef::FA3::Validator.errors_for(invoice.to_xml)).to be_empty
      expect(document.xpath("//Fa/FaWiersz/*").map(&:name)).to eq(%w[NrWierszaFa P_7])
    end

    it "takes its totals from the summary it states, not from its rows" do
      expect(invoice.gross_total).to eq(BigDecimal("450"))
      expect(invoice.net_by_rate).to eq({})
    end

    it "round-trips to an equal invoice" do
      expect(Ksef::FA3.parse(invoice.to_xml)).to eq(invoice)
    end

    it "reproduces its golden byte for byte, losing nothing" do
      xml = File.read(FA3Corpus.path("golden/upr_simplified.xml"), encoding: "UTF-8")
      parsed = Ksef::FA3.parse(xml)

      expect(parsed.to_xml).to eq(xml)
      expect(parsed).to be_fully_mapped
    end
  end

  # The safety rule. Without it, an unpriced row on an invoice that adds its rows up would be
  # silently absent from the tax base — and neither the XSD nor `#unmapped_elements` can see
  # that, the first being blind to arithmetic and the second to values.
  describe "tier 1, where the summary is derived from the rows" do
    def vat_invoice(lines)
      Ksef::FA3::Invoice.new(seller: seller, buyer: buyer, number: "FV/1",
                             issue_date: Date.new(2026, 2, 15), lines: lines)
    end

    it "refuses a row that states no amount" do
      expect(vat_invoice([named_only]).errors.map(&:to_s))
        .to include(/lines\[0\]: states no amount, and this invoice derives its summary/)
    end

    it "refuses a row that states an amount with no rate to bucket it under" do
      expect(vat_invoice([priced(vat_rate: nil)]).errors.map(&:to_s))
        .to include(/lines\[0\].vat_rate: states an amount but no P_12 rate code/)
    end

    it "says nothing about either on an invoice that states its summary" do
      stated = invoice(lines: [named_only, priced(vat_rate: nil)])

      expect(stated.errors).to be_empty
    end

    it "still checks the rate against the schema when one is given" do
      expect(invoice(lines: [priced(vat_rate: "24")]).errors.map(&:to_s))
        .to include(/lines\[0\].vat_rate: "24" is not one of TStawkaPodatku's permitted values/)
    end

    # The summary skips what it cannot place, which is why tier 1 has to object: without the
    # rule the document would simply understate the tax base.
    it "would otherwise have left the amount out of the summary entirely" do
      mixed = invoice(totals: nil, invoice_type: "VAT",
                      lines: [priced, priced(vat_rate: nil), named_only])

      expect(mixed.net_total).to eq(BigDecimal("100"))
      expect(mixed.errors.map(&:field)).to include("lines[1].vat_rate", "lines[2]")
    end

    # `#net_by_rate` and `#vat_rounded_per_line` both skip an unsummarised row, and only the
    # first was tested — the second's guard was the one branch this round left uncovered, and
    # dropping it left the suite green. It matters because a rateless row would otherwise key
    # the VAT summary under nil while the net summary skipped it, so the two would disagree
    # about which buckets exist.
    it "skips the same rows in the VAT summary as in the net one" do
      mixed = invoice(totals: nil, invoice_type: "VAT",
                      lines: [priced, priced(vat_rate: nil), named_only])

      expect(mixed.vat_by_rate.keys).to eq(mixed.net_by_rate.keys)
      expect(mixed.vat_by_rate.keys).to eq(["23"])
    end
  end

  # Przykład 7 was refused until 2026-08-26 — the only Ministry correction this model could not
  # read — because its single row names goods, a CN code and a quantity, and no amount.
  describe "the same shape on a collective correction" do
    let(:parsed) { Ksef::FA3.parse(FA3Corpus.read("mf-samples/przyklad-07.xml")) }

    it "reads Przykład 7's descriptive row" do
      expect(parsed.lines.size).to eq(1)
      expect(parsed.lines.first).to have_attributes(name: "lodówka Zimnotech mk1", net: nil)
    end

    it "validates and round-trips, with the CN code visible as the one thing lost" do
      expect(parsed.errors).to be_empty
      expect(Ksef::FA3.parse(parsed.to_xml)).to eq(parsed)
      expect(parsed.unmapped_elements).to include("Faktura/Fa/FaWiersz/CN")
    end
  end
end
