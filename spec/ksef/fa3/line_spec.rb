# frozen_string_literal: true

RSpec.describe Ksef::FA3::Line do
  def line(**overrides)
    described_class.new(name: "Consulting", quantity: 10, unit: "godz.",
                        net_unit_price: "150", vat_rate: "23", **overrides)
  end

  # "Amounts are BigDecimal throughout" is an invariant of the object, not a promise kept by
  # whichever method looks at them next. Converting on the way in is also what makes a built
  # line equal a parsed one (DESIGN.md §7.6) rather than merely `==` with a different #hash.
  describe "converting numbers on the way in" do
    it "stores integers, strings and decimals alike as BigDecimal" do
      expect(line(quantity: 10).quantity).to eql(BigDecimal("10"))
      expect(line(net_unit_price: "150.00").net_unit_price).to eql(BigDecimal("150"))
      expect(line(net_amount: BigDecimal("1500")).net_amount).to eql(BigDecimal("1500"))
    end

    it "makes a line built from an Integer identical to one parsed from a string" do
      from_integer = line(quantity: 10, net_unit_price: 150, net_amount: 1500)
      from_document = line(quantity: "10", net_unit_price: "150.00", net_amount: "1500.00")

      expect(from_integer).to eq(from_document)
      expect(from_integer.hash).to eq(from_document.hash)
    end

    # Quantity and unit price are both optional in TFaWiersz, so nil has to survive.
    it "leaves nil alone" do
      expect(line(quantity: nil, net_amount: "100").quantity).to be_nil
      expect(line.net_amount).to be_nil
    end

    # `TKwotowy` is fractionDigits="2" and `TIlosci` fractionDigits="6", so a finer value is
    # not something FA(3) can express. Rounding on the way in means the model reports the
    # figure the document will carry, and `#net` agrees with the invoice as printed.
    it "rounds an amount to the two places its element allows" do
      expect(line(net_unit_price: "150.125").net_unit_price).to eq(BigDecimal("150.13"))
      expect(line(net_amount: "100.004").net_amount).to eq(BigDecimal("100.00"))
    end

    it "rounds a quantity to the six places its element allows" do
      expect(line(quantity: "1.12345678").quantity).to eq(BigDecimal("1.123457"))
    end

    # A quantity finer than TIlosci allows used to reach the document unrounded, which is a
    # schema rejection rather than a rounding difference.
    it "keeps a fine quantity schema-valid" do
      content = line(quantity: "1.12345678").to_fa3(row_number: 1)

      expect(content["P_8B"]).to eq("1.123457")
    end

    it "makes net agree with the price the document shows" do
      # 3 x 150.13 (the representable price), not 3 x 150.125.
      expect(line(quantity: 3, net_unit_price: "150.125", net_amount: nil).net)
        .to eq(BigDecimal("450.39"))
    end

    # DESIGN.md §4.4. Rejected at construction, where the caller can see which line it
    # passed, rather than at serialisation.
    it "refuses a Float at construction" do
      expect { line(net_unit_price: 150.0) }
        .to raise_error(Ksef::ValidationError, /Float is not allowed/)
    end
  end

  describe "#net" do
    it "multiplies quantity by unit price when no net is stated" do
      expect(line.net).to eq(BigDecimal("1500"))
    end

    # An ERP is allowed to be the source of truth, and a discounted line is the ordinary
    # case where the two disagree — upstream's own corpus has 20 × 1000 with a net of 18000.
    it "prefers a stated net over the product" do
      expect(line(net_amount: "18000").net).to eq(BigDecimal("18000"))
    end

    it "says what is missing when it can neither read nor derive one" do
      expect { line(quantity: nil, net_unit_price: nil).net }
        .to raise_error(Ksef::ValidationError, /"Consulting" needs either net_amount, or both/)
    end
  end

  describe "#vat and #gross" do
    it "applies the rate percentage to the net" do
      expect(line.vat).to eq(BigDecimal("345"))
      expect(line.gross).to eq(BigDecimal("1845"))
    end

    # Half the TStawkaPodatku values are procedures, not percentages (§8.1a).
    it "charges nothing on a non-numeric rate code" do
      expect(line(vat_rate: "zw").vat).to eq(0)
      expect(line(vat_rate: "oo").gross).to eq(BigDecimal("1500"))
    end
  end

  # Every child of TFaWiersz except NrWierszaFa is minOccurs="0", and the parser accepts a row
  # stating only its net. Writing those fields empty produced `<P_8A/>`, which fails
  # TZnakowy512 — and formatting a nil quantity raised, which took #unmapped_elements with it.
  describe "#to_fa3 with optional fields absent" do
    it "omits them rather than writing empty elements" do
      content = described_class.new(name: nil, quantity: nil, unit: nil, net_unit_price: nil,
                                    vat_rate: "23", net_amount: "100").to_fa3(row_number: 1)

      expect(content).to eq("NrWierszaFa" => 1, "P_11" => "100.00", "P_12" => "23")
    end

    it "omits P_12 for a rate-less line" do
      content = described_class.new(name: "X", quantity: nil, unit: nil, net_unit_price: nil,
                                    vat_rate: nil, net_amount: "10").to_fa3(row_number: 1)

      expect(content).not_to have_key("P_12")
      expect(content).to eq("NrWierszaFa" => 1, "P_7" => "X", "P_11" => "10.00")
    end

    it "still writes the ones that are present" do
      content = line(name: nil).to_fa3(row_number: 2)

      expect(content).not_to have_key("P_7")
      expect(content["P_8A"]).to eq("godz.")
      expect(content["P_11"]).to eq("1500.00")
    end

    it "serialises a net-only row into a schema-valid document" do
      lump = described_class.new(name: "Ryczałt", quantity: nil, unit: nil, net_unit_price: nil,
                                 vat_rate: "23", net_amount: "100")
      invoice = Ksef::FA3::Invoice.new(
        seller: Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME",
                                       address: Ksef::FA3::Address.new(line1: "Prosta 1")),
        buyer: Ksef::FA3::Subject.new(nip: "1111111111", name: "Klient",
                                      address: Ksef::FA3::Address.new(line1: "Długa 2")),
        number: "FV/1", issue_date: Date.new(2026, 8, 24), lines: [lump]
      )

      expect(Ksef::FA3::Validator.errors_for(invoice.to_xml)).to be_empty
    end
  end

  # Data#with skips a custom initialize on Ruby 3.2, this gem's floor — so the no-Float rule
  # was bypassable through a public method there (see FA3::Canonical).
  describe "#with" do
    it "refuses a Float, on every supported Ruby" do
      expect { line.with(quantity: 0.1) }
        .to raise_error(Ksef::ValidationError, /Float is not allowed/)
    end

    it "converts the replacement value like the constructor does" do
      expect(line.with(net_unit_price: "12.50").net_unit_price).to eql(BigDecimal("12.5"))
    end
  end
end
