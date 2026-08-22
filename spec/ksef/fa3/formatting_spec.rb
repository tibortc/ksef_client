# frozen_string_literal: true

RSpec.describe Ksef::FA3::Formatting do
  describe ".amount" do
    it "always emits exactly two decimal places" do
      expect(described_class.amount(1500)).to eq("1500.00")
      expect(described_class.amount(BigDecimal("1500.5"))).to eq("1500.50")
      expect(described_class.amount(0)).to eq("0.00")
    end

    it "never emits scientific notation, which the schema rejects" do
      expect(described_class.amount(BigDecimal("1234567.891"))).to eq("1234567.89")
      expect(described_class.amount(BigDecimal("1e10"))).to eq("10000000000.00")
    end

    it "handles negatives" do
      expect(described_class.amount(BigDecimal("-12.1"))).to eq("-12.10")
    end

    it "rounds half-up at two places" do
      expect(described_class.amount(BigDecimal("0.005"))).to eq("0.01")
    end
  end

  # DESIGN.md §4.4: Float is forbidden in any monetary path. 0.01 has no exact binary
  # representation, and a rounding error in a tax document is a real problem.
  it "refuses Float outright rather than coercing it" do
    expect { described_class.amount(1.5) }
      .to raise_error(Ksef::ValidationError, /Float is not allowed/)
    expect { described_class.decimal(0.1) }
      .to raise_error(Ksef::ValidationError, /Float is not allowed/)
  end

  describe ".decimal" do
    it "passes a BigDecimal through untouched" do
      value = BigDecimal("1.23")
      expect(described_class.decimal(value)).to be(value)
    end

    it "accepts an Integer and a decimal String" do
      expect(described_class.decimal(5)).to eq(BigDecimal(5))
      expect(described_class.decimal("5.25")).to eq(BigDecimal("5.25"))
    end

    # A Rational can arrive from exact arithmetic elsewhere and is safe to convert, unlike
    # a Float — but it needs an explicit precision.
    it "accepts a Rational" do
      expect(described_class.decimal(Rational(1, 4))).to eq(BigDecimal("0.25"))
    end

    it "rejects a type it cannot represent exactly" do
      expect { described_class.decimal(:nope) }
        .to raise_error(Ksef::ValidationError, /Cannot convert Symbol/)
    end
  end

  describe ".quantity" do
    it "drops a meaningless trailing .0 on a whole count" do
      expect(described_class.quantity(10)).to eq("10")
    end

    it "keeps genuine fractional precision, unlike amounts" do
      expect(described_class.quantity(BigDecimal("1.5"))).to eq("1.5")
      expect(described_class.quantity(BigDecimal("0.001"))).to eq("0.001")
    end
  end

  describe ".flag" do
    # The schema spells booleans as 1/2, and the inversion is easy to get backwards.
    it "maps true to 1 and false to 2" do
      expect(described_class.flag(true)).to eq("1")
      expect(described_class.flag(false)).to eq("2")
    end

    it "treats nil as no" do
      expect(described_class.flag(nil)).to eq("2")
    end

    it "passes through the codes themselves" do
      expect(described_class.flag("1")).to eq("1")
      expect(described_class.flag("2")).to eq("2")
    end

    it "rejects anything else" do
      expect { described_class.flag("yes") }.to raise_error(Ksef::ValidationError, /boolean-ish/)
    end
  end

  describe ".date and .date_time" do
    it "formats a Date as ISO-8601" do
      expect(described_class.date(Date.new(2026, 8, 22))).to eq("2026-08-22")
    end

    it "parses a string date" do
      expect(described_class.date("2026-08-22")).to eq("2026-08-22")
    end

    it "formats a Time as UTC xsd:dateTime" do
      expect(described_class.date_time(Time.utc(2026, 8, 22, 10, 0, 0))).to eq("2026-08-22T10:00:00Z")
    end

    it "passes a pre-formatted string through, for callers with their own timestamp" do
      expect(described_class.date_time("2026-08-22T10:00:00Z")).to eq("2026-08-22T10:00:00Z")
    end

    it "normalises a DateTime to UTC" do
      expect(described_class.date_time(DateTime.new(2026, 8, 22, 12, 0, 0, "+02:00")))
        .to eq("2026-08-22T10:00:00Z")
    end

    it "treats a bare Date as midnight" do
      expect(described_class.date_time(Date.new(2026, 8, 22))).to eq("2026-08-22T00:00:00Z")
    end

    it "coerces a Time to a date via to_date" do
      expect(described_class.date(Time.utc(2026, 8, 22, 23, 59, 59))).to eq("2026-08-22")
    end

    it "converts a non-UTC time rather than pretending" do
      expect(described_class.date_time(Time.new(2026, 8, 22, 12, 0, 0, "+02:00")))
        .to eq("2026-08-22T10:00:00Z")
    end
  end
end
