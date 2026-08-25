# frozen_string_literal: true

require "nokogiri"
require_relative "../../support/fa3_corpus"

# `ZAL` and `ROZ` — the advance invoice and the settlement invoice that closes it out
# (docs/REFERENCE.md §8.5), end to end: the value objects, the DSL, what gets written, what
# comes back, and what tier 1 says about it.
RSpec.describe "FA(3) advance and settlement invoices" do
  def seller
    Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME sp. z o.o.",
                           address: Ksef::FA3::Address.new(line1: "Prosta 1, 00-001 Warszawa"))
  end

  def buyer
    Ksef::FA3::Subject.new(nip: "1111111111", name: "Klient S.A.",
                           address: Ksef::FA3::Address.new(line1: "Długa 2, 30-001 Kraków"))
  end

  def order_line(**overrides)
    Ksef::FA3::OrderLine.new(name: "mieszkanie 50m^2", quantity: 1, unit: "szt.",
                             net_unit_price: "300000", net_amount: "300000",
                             vat_amount: "69000", vat_rate: "23", **overrides)
  end

  def order(**overrides) = Ksef::FA3::Order.new(total: "375150", lines: [order_line], **overrides)

  def invoice(**overrides)
    Ksef::FA3::Invoice.new(
      seller: seller, buyer: buyer, number: "FZ/2026/02/150",
      issue_date: Date.new(2026, 2, 15), issued_at: Time.utc(2026, 2, 15),
      invoice_type: "ZAL", order: order,
      totals: Ksef::FA3::Totals.new(gross: "20000",
                                    buckets: { "P_13_1" => "16260.16", "P_14_1" => "3739.84" }),
      **overrides
    )
  end

  def rendered(document) = Nokogiri::XML(document.to_xml).remove_namespaces!

  describe Ksef::FA3::AdvanceInvoice do
    it "writes the KSeF number alone when the advance invoice was issued through KSeF" do
      expect(described_class.new(ksef_number: "5265877635-20250826-0100001AF629-AF").to_fa3)
        .to eq("NrKSeFFaZaliczkowej" => "5265877635-20250826-0100001AF629-AF")
    end

    # The choice is inverted from `DaneFaKorygowanej`'s: here the *marker* pairs with the
    # plain number, not with the KSeF one.
    it "writes the marker and the plain number when it was issued outside KSeF" do
      expect(described_class.new(number: "FZ/2026/02/150").to_fa3)
        .to eq("NrKSeFZN" => "1", "NrFaZaliczkowej" => "FZ/2026/02/150")
    end

    it "refuses naming both, which is not a document that exists" do
      expect { described_class.new(ksef_number: "x", number: "y") }
        .to raise_error(Ksef::ValidationError, /exactly one of ksef_number/)
    end

    it "refuses naming neither" do
      expect { described_class.new }.to raise_error(Ksef::ValidationError, /exactly one of ksef_number/)
    end

    it "re-runs the constructor through #with" do
      expect { described_class.new(number: "FZ/1").with(ksef_number: "x") }
        .to raise_error(Ksef::ValidationError, /exactly one of ksef_number/)
    end
  end

  describe Ksef::FA3::Order do
    it "refuses an order with no positions" do
      expect { described_class.new(total: "1", lines: []) }
        .to raise_error(Ksef::ValidationError, /needs at least one position/)
    end

    it "accepts a single position without wrapping it in an Array" do
      expect(described_class.new(total: "1", lines: order_line).lines).to eq([order_line])
    end

    it "rounds its total to the scale TKwotowy permits" do
      expect(described_class.new(total: "1.005", lines: order_line).total).to eq(BigDecimal("1.01"))
    end

    it "refuses a Float total, as everywhere money flows" do
      expect { described_class.new(total: 1.5, lines: order_line) }
        .to raise_error(Ksef::ValidationError, /Float is not allowed/)
    end

    # The same rule Invoice.positioned follows: a number that merely repeats its position
    # carries nothing, and storing it would break the round-trip law.
    it "drops a row number that merely repeats its position" do
      expect(described_class.new(total: "1", lines: [order_line(row_number: 1)]).lines.first.row_number)
        .to be_nil
    end

    it "keeps one that does not, which is what pairs a KOR_ZAL's before and after" do
      paired = described_class.new(total: "1", lines: [order_line, order_line(row_number: 1)])

      expect(paired.lines.map(&:row_number)).to eq([nil, 1])
    end

    it "re-runs the constructor through #with" do
      expect { order.with(lines: []) }.to raise_error(Ksef::ValidationError, /at least one position/)
    end
  end

  describe Ksef::FA3::OrderLine do
    # `Line#net` derives from quantity × price because a VAT invoice's summary is computed
    # from it. An order's rows feed nothing, so a derivation here would have no consumer.
    it "derives nothing, omitting what the order does not state" do
      written = described_class.new(name: "x", quantity: 2, unit: "szt.",
                                    net_unit_price: "10").to_fa3(row_number: 1)

      expect(written).to eq("NrWierszaZam" => 1, "P_7Z" => "x", "P_8AZ" => "szt.",
                            "P_8BZ" => "2", "P_9AZ" => "10.00")
    end

    # `P_11VatZ` has no counterpart in `FaWiersz`, where the tax is computed from the rate.
    it "states its own tax rather than computing it from the rate" do
      expect(described_class.new(vat_amount: "69000", vat_rate: "23").to_fa3(row_number: 1))
        .to include("P_11VatZ" => "69000.00", "P_12Z" => "23")
    end

    it "marks the state before a correction, as FaWiersz does" do
      expect(described_class.new(state_before: true).to_fa3(row_number: 2))
        .to include("StanPrzedZ" => "1")
      expect(described_class.new.to_fa3(row_number: 2).keys).not_to include("StanPrzedZ")
    end
  end

  describe "what a ZAL writes" do
    let(:document) { rendered(invoice) }

    it "is schema-valid, and carries no FaWiersz at all" do
      expect(Ksef::FA3::Validator.errors_for(invoice.to_xml)).to be_empty
      expect(document.xpath("//Fa/FaWiersz")).to be_empty
      expect(document.at_xpath("//Fa/Zamowienie/WartoscZamowienia").text).to eq("375150.00")
    end

    # WartoscZamowienia is the whole order including tax; P_15 is the advance received. In
    # the Ministry's Przykład 10 they are 375 150 against 20 000.
    it "keeps the order's own value apart from the amount this invoice charges" do
      expect(invoice.gross_total).to eq(BigDecimal("20000"))
      expect(invoice.order.total).to eq(BigDecimal("375150"))
    end

    it "round-trips to an equal invoice" do
      expect(Ksef::FA3.parse(invoice.to_xml)).to eq(invoice)
    end
  end

  describe "what a ROZ writes" do
    let(:settlement) do
      invoice(invoice_type: "ROZ", order: nil, number: "FV/2026/08/12",
              advances: [Ksef::FA3::AdvanceInvoice.new(ksef_number: "5265877635-20250826-0100001AF629-AF"),
                         Ksef::FA3::AdvanceInvoice.new(number: "FZ/2026/02/150")],
              lines: [Ksef::FA3::Line.new(name: "mieszkanie 50m^2", quantity: 1, unit: "szt.",
                                          net_unit_price: "307500", net_amount: "307500",
                                          vat_rate: "8")])
    end

    it "names every advance invoice it settles, in either form" do
      names = rendered(settlement).xpath("//Fa/FakturaZaliczkowa")

      expect(names.size).to eq(2)
      expect(names.first.at_xpath("NrKSeFFaZaliczkowej").text).to end_with("AF629-AF")
      expect(names.last.at_xpath("NrKSeFZN").text).to eq("1")
    end

    # The rows describe the goods; the buckets describe what is left to pay after the advance,
    # which this document does not contain enough to compute. Deriving would state 307 500.
    it "states a summary its own rows do not add up to" do
      expect(settlement.gross_total).to eq(BigDecimal("20000"))
      expect(settlement.lines.sum(BigDecimal(0), &:net)).to eq(BigDecimal("307500"))
      expect(Ksef::FA3::Validator.errors_for(settlement.to_xml)).to be_empty
    end

    it "round-trips to an equal invoice" do
      expect(Ksef::FA3.parse(settlement.to_xml)).to eq(settlement)
    end
  end

  describe "the goldens" do
    # If these fail, either the serializer changed or the schema did. Regenerate deliberately
    # and read the diff — do not update the fixture to make it pass.
    { "golden/zal_order.xml" => "ZAL", "golden/roz_settlement.xml" => "ROZ" }.each do |relative, type|
      it "#{relative} is reproduced byte for byte and loses nothing" do
        xml = File.read(FA3Corpus.path(relative), encoding: "UTF-8")
        parsed = Ksef::FA3.parse(xml)

        expect(parsed.invoice_type).to eq(type)
        expect(parsed.to_xml).to eq(xml)
        expect(parsed).to be_fully_mapped
      end
    end
  end

  describe "the DSL" do
    def built(&block)
      Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: "Prosta 1, 00-001 Warszawa"
        f.buyer nip: "1111111111", name: "Klient S.A.", address: "Długa 2, 30-001 Kraków"
        f.number "FZ/2026/02/150"
        f.issue_date Date.new(2026, 2, 15)
        block.call(f)
      end
    end

    let(:advance) do
      built do |f|
        f.invoice_type "ZAL"
        f.order total: "375150"
        f.order_line name: "mieszkanie 50m^2", qty: 1, unit: "szt.", net_unit_price: "300000",
                     net_amount: "300000", vat_amount: "69000", vat: "23"
        f.totals gross: "20000", net: { "23" => "16260.16" }, vat: { "23" => "3739.84" }
      end
    end

    it "builds a ZAL that validates and needs no FaWiersz" do
      expect(advance.errors).to be_empty
      expect(advance.lines).to be_empty
      expect(advance.order.lines.size).to eq(1)
    end

    it "takes the same shorthand for an order position as for a line" do
      expect(advance.order.lines.first)
        .to have_attributes(quantity: BigDecimal(1), vat_rate: "23")
    end

    it "builds a ROZ naming the advance invoices it settles" do
      settlement = built do |f|
        f.invoice_type "ROZ"
        f.settles ksef_number: "5265877635-20250826-0100001AF629-AF"
        f.settles number: "FZ/2026/01/001"
        f.line name: "mieszkanie", qty: 1, unit: "szt.", net_unit_price: "10", net_amount: "10", vat: "23"
        f.totals gross: "10.00", net: { "23" => "8.13" }, vat: { "23" => "1.87" }
      end

      expect(settlement.errors).to be_empty
      expect(settlement.advances.map(&:number)).to eq([nil, "FZ/2026/01/001"])
    end

    # `Order.new` would otherwise raise `ArgumentError: missing keyword` — outside this gem's
    # hierarchy, and from a DSL whose whole job is naming the missing field.
    it "names a missing order total rather than raising ArgumentError" do
      expect { built { |f| f.order_line name: "x" } }
        .to raise_error(Ksef::ValidationError, /An order needs a total/)
    end

    it "reports a misspelled key for each of the three new calls" do
      { order: :value, order_line: :nazwa, settles: :nr }.each do |call, bad_key|
        expect { built { |f| f.public_send(call, bad_key => "x") } }
          .to raise_error(Ksef::ValidationError, /Unknown .*option\(s\) #{bad_key.inspect}/)
      end
    end

    it "leaves an ordinary invoice with neither an order nor an advance" do
      plain = built do |f|
        f.line name: "Consulting", qty: 1, unit: "szt.", net_unit_price: 100, vat: "23"
      end

      expect(plain.order).to be_nil
      expect(plain.advances).to be_empty
    end
  end

  describe "tier 1" do
    it "requires a stated summary once an order is present" do
      expect(invoice(totals: nil, lines: [Ksef::FA3::Line.new(name: "x", quantity: 1, unit: "szt.",
                                                              net_unit_price: "10", vat_rate: "23")]).errors
              .map(&:to_s))
        .to include(/totals: is required when an order is stated/)
    end

    it "requires one once an advance invoice is settled" do
      settling = invoice(invoice_type: "ROZ", order: nil, totals: nil,
                         advances: [Ksef::FA3::AdvanceInvoice.new(number: "FZ/1")],
                         lines: [Ksef::FA3::Line.new(name: "x", quantity: 1, unit: "szt.",
                                                     net_unit_price: "10", vat_rate: "23")])

      expect(settling.errors.map(&:to_s)).to include(/totals: is required when an advance invoice is settled/)
    end

    it "names an order position whose rate the schema does not define" do
      expect(invoice(order: order(lines: [order_line(vat_rate: "24")])).errors.map(&:to_s))
        .to include(/order.lines\[0\].vat_rate: "24" is not one of TStawkaPodatku's permitted values/)
    end

    it "says nothing about an order position that states no rate, which is optional" do
      expect(invoice(order: order(lines: [order_line(vat_rate: nil)])).errors).to be_empty
    end

    it "reports an order of the wrong class rather than letting to_xml raise" do
      expect(invoice(order: Object.new).errors.map(&:to_s)).to eq(["order: is not a Ksef::FA3::Order"])
    end

    it "reports an order position of the wrong class" do
      broken = Ksef::FA3::Order.new(total: "1", lines: [Object.new])

      expect(invoice(order: broken).errors.map(&:to_s)).to eq(["order.lines[0]: is not a Ksef::FA3::OrderLine"])
    end

    it "reports an advance reference of the wrong class" do
      expect(invoice(advances: [Object.new]).errors.map(&:to_s))
        .to eq(["advances[0]: is not a Ksef::FA3::AdvanceInvoice"])
    end

    it "names an advance invoice number that exceeds TZnakowy" do
      expect(invoice(advances: [Ksef::FA3::AdvanceInvoice.new(number: "x" * 257)]).errors.map(&:field))
        .to include("advances[0].number")
    end

    # The schema's choice again. Repairing a document that states neither branch would assert
    # where the advance invoice had been issued — a fact nobody wrote down.
    it "refuses a FakturaZaliczkowa that states neither branch" do
      settlement = invoice(invoice_type: "ROZ", order: nil,
                           advances: [Ksef::FA3::AdvanceInvoice.new(number: "FZ/1")])
      neither = settlement.to_xml.sub(%r{<NrKSeFZN>1</NrKSeFZN>\s*<NrFaZaliczkowej>[^<]*</NrFaZaliczkowej>}m, "")

      expect { Ksef::FA3.parse(neither) }
        .to raise_error(Ksef::ValidationError, /states neither NrKSeFFaZaliczkowej nor NrFaZaliczkowej/)
    end

    it "passes a sound ZAL" do
      expect(invoice.errors).to be_empty
    end
  end
end
