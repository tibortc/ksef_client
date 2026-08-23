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
end
