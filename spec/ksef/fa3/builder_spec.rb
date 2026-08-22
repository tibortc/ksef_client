# frozen_string_literal: true

# Required explicitly: unlike the serializer's own spec, nothing here touches a constant
# that would autoload it first, and `Nokogiri::XML(invoice.to_xml)` resolves the receiver
# before evaluating the argument.
require "nokogiri"

RSpec.describe Ksef::FA3::Builder do
  # The minimum a valid invoice needs, so each example can vary one thing.
  def complete(&block)
    Ksef::FA3.build do |f|
      f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: { street: "Prosta 1", city: "Warszawa",
                                                                      postal_code: "00-001" }
      f.buyer nip: "1111111111", name: "Klient S.A.", address: { street: "Długa 2", city: "Kraków",
                                                                 postal_code: "30-001" }
      f.number "FV/2026/08/001"
      f.issue_date Date.new(2026, 8, 22)
      f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23"
      block&.call(f)
    end
  end

  def rendered(invoice) = Nokogiri::XML(invoice.to_xml).remove_namespaces!

  describe "Ksef::FA3.build" do
    # DESIGN.md §8 states this snippet must run verbatim by 0.1.0. It is the headline
    # example in the README, so a regression here is the most visible kind.
    it "runs the DESIGN.md §8 snippet and produces a schema-valid document" do
      invoice = complete

      expect(invoice).to be_a(Ksef::FA3::Invoice)
      expect(invoice.net_total).to eq(BigDecimal("1500"))
      expect(invoice.vat_total).to eq(BigDecimal("345"))
      expect(invoice.gross_total).to eq(BigDecimal("1845"))
      expect { invoice.validate! }.not_to raise_error
    end

    it "requires a block, rather than returning an unusable empty builder" do
      expect { Ksef::FA3.build }.to raise_error(ArgumentError, /requires a block/)
    end
  end

  describe "subjects" do
    it "coerces a Hash address into an Address" do
      expect(rendered(complete).at_xpath("//Podmiot1/Adres/AdresL1").text).to eq("Prosta 1, 00-001 Warszawa")
    end

    it "accepts an Address instance unchanged" do
      invoice = complete { |f| f.seller nip: "9999999999", name: "ACME", address: Ksef::FA3::Address.new(line1: "X 1") }

      expect(rendered(invoice).at_xpath("//Podmiot1/Adres/AdresL1").text).to eq("X 1")
    end

    it "accepts a pre-formatted String as the first address line" do
      invoice = complete { |f| f.buyer nip: "1111111111", name: "Klient", address: "Długa 2, 30-001 Kraków" }

      expect(rendered(invoice).at_xpath("//Podmiot2/Adres/AdresL1").text).to eq("Długa 2, 30-001 Kraków")
    end

    it "passes the buyer's mandatory flags through" do
      invoice = complete do |f|
        f.buyer nip: "1111111111", name: "Gmina", address: "X 1", local_government_unit: true
      end

      expect(rendered(invoice).at_xpath("//Podmiot2/JST").text).to eq("1")
    end

    it "rejects an address that is neither Address, Hash nor String" do
      expect { complete { |f| f.seller nip: "9999999999", name: "X", address: 42 } }
        .to raise_error(Ksef::ValidationError, /seller address must be/)
    end

    it "names every missing field at once" do
      expect { complete { |f| f.seller name: "X" } }
        .to raise_error(Ksef::ValidationError, /Incomplete seller, missing nip, address/)
    end

    it "rejects an unknown subject key" do
      expect { complete { |f| f.seller nip: "9999999999", name: "X", address: "Y", vat_id: "Z" } }
        .to raise_error(Ksef::ValidationError, /Unknown seller subject option\(s\) :vat_id/)
    end

    it "rejects an unknown address key, naming the address rather than the subject" do
      expect { complete { |f| f.seller nip: "9999999999", name: "X", address: { postcode: "00-001" } } }
        .to raise_error(Ksef::ValidationError, /Unknown seller address option\(s\) :postcode/)
    end

    # No aliases are defined for subjects, so the message must not dangle a "Shorthand:"
    # clause with nothing after it.
    it "omits the shorthand hint where there is no shorthand" do
      expect { complete { |f| f.seller nip: "9999999999", name: "X", address: "Y", vat_id: "Z" } }
        .to raise_error(Ksef::ValidationError) { |error| expect(error.message).not_to include("Shorthand") }
    end
  end

  describe "lines" do
    it "accepts the canonical names as well as the shorthand" do
      invoice = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "A", address: "X 1"
        f.buyer nip: "1111111111", name: "B", address: "Y 2"
        f.number "1"
        f.issue_date Date.new(2026, 8, 22)
        f.line name: "Item", quantity: 2, unit: "szt.", net_unit_price: 50, vat_rate: "23"
      end

      expect(invoice.net_total).to eq(BigDecimal("100"))
    end

    it "rejects passing both a shorthand and its canonical name" do
      expect { complete { |f| f.line name: "X", qty: 1, quantity: 2, unit: "szt.", net_unit_price: 1, vat: "23" } }
        .to raise_error(Ksef::ValidationError, /Pass either qty: or quantity: to line, not both/)
    end

    it "rejects an unknown line key and advertises the shorthand" do
      expect { complete { |f| f.line name: "X", price: 1 } }
        .to raise_error(Ksef::ValidationError, /Unknown line option\(s\) :price.*Shorthand: qty for quantity/m)
    end

    it "accumulates lines in call order and numbers them on serialisation" do
      invoice = complete do |f|
        f.line name: "Second", qty: 1, unit: "szt.", net_unit_price: 10, vat: "23"
        f.line name: "Third", qty: 1, unit: "szt.", net_unit_price: 20, vat: "23"
      end
      rows = rendered(invoice).xpath("//FaWiersz")

      expect(rows.map { |r| r.at_xpath("P_7").text }).to eq(%w[Consulting Second Third])
      expect(rows.map { |r| r.at_xpath("NrWierszaFa").text }).to eq(%w[1 2 3])
    end

    it "passes an explicit net_amount through instead of computing it" do
      invoice = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "A", address: "X 1"
        f.buyer nip: "1111111111", name: "B", address: "Y 2"
        f.number "1"
        f.issue_date Date.new(2026, 8, 22)
        f.line name: "Item", qty: 3, unit: "szt.", net_unit_price: 10, vat: "23", net_amount: BigDecimal("29.99")
      end

      expect(invoice.net_total).to eq(BigDecimal("29.99"))
    end
  end

  describe "optional invoice fields" do
    it "sets the currency" do
      expect(rendered(complete { |f| f.currency "EUR" }).at_xpath("//Fa/KodWaluty").text).to eq("EUR")
    end

    it "sets the generation timestamp" do
      invoice = complete { |f| f.issued_at Time.utc(2026, 8, 22, 10, 30, 0) }

      expect(rendered(invoice).at_xpath("//Naglowek/DataWytworzeniaFa").text).to eq("2026-08-22T10:30:00Z")
    end

    it "sets the invoice type" do
      expect(rendered(complete { |f| f.invoice_type "KOR" }).at_xpath("//Fa/RodzajFaktury").text).to eq("KOR")
    end

    it "selects the summary rounding strategy" do
      expect(complete { |f| f.rounding :per_summary }.rounding).to eq(:per_summary)
    end

    it "still rejects an unknown rounding strategy, via the model" do
      expect { complete { |f| f.rounding :nearest_zloty } }
        .to raise_error(Ksef::ValidationError, /Unknown rounding strategy/)
    end
  end

  describe "completeness" do
    it "reports every missing required field in one message" do
      expect { Ksef::FA3.build { |f| f.number "1" } }
        .to raise_error(Ksef::ValidationError, /missing seller, buyer, issue_date/)
    end

    it "defers the no-lines complaint to the model, so the rule lives in one place" do
      expect do
        Ksef::FA3.build do |f|
          f.seller nip: "9999999999", name: "A", address: "X 1"
          f.buyer nip: "1111111111", name: "B", address: "Y 2"
          f.number "1"
          f.issue_date Date.new(2026, 8, 22)
        end
      end.to raise_error(Ksef::ValidationError, /at least one line/)
    end

    # Overwriting is the documented behaviour: a builder whose setters raised on reuse
    # would make conditional construction awkward for no real safety gain.
    it "lets a later call to a single-value field win" do
      invoice = complete do |f|
        f.number "FV/OVERRIDDEN"
        f.number "FV/FINAL"
      end

      expect(rendered(invoice).at_xpath("//Fa/P_2").text).to eq("FV/FINAL")
    end
  end
end
