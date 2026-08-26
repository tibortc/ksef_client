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

    # BigDecimal's second argument is significant digits, not decimal places. AMOUNT_SCALE + 10
    # read as "12 decimal places" and meant "12 significant digits", truncating large amounts.
    it "keeps a large Rational exact" do
      expect(described_class.decimal(Rational(1_234_567_890_123_456, 100)).to_s("F"))
        .to eq("12345678901234.56")
    end

    # Empty and malformed numeric text is what a rejected document contains, so it must arrive
    # as this gem's own error rather than a bare ArgumentError from BigDecimal.
    it "wraps unreadable numeric text in a ValidationError" do
      ["", "abc", "12,50"].each do |text|
        expect { described_class.decimal(text) }
          .to raise_error(Ksef::ValidationError, /Cannot read #{Regexp.escape(text.inspect)} as a decimal/)
      end
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

  # For the handful of elements restricting xsd:integer — TypKorekty, NrWierszaFa — whose
  # value space is integers, so the lexical form is not the value.
  describe ".integer" do
    # **`"010"`, not `"03"`.** The original example used `"03"`, where octal and decimal agree
    # — so it passed either way and the shipped octal bug sat squarely in its blind spot.
    # `NrWierszaFa` is `TNaturalny`, whose lexical space permits leading zeros, and
    # fixed-width row numbering is an ordinary ERP convention.
    it "reads leading zeros as decimal, not as octal" do
      expect(described_class.integer("010")).to eq(10)
      expect(described_class.integer("08")).to eq(8)
      expect(described_class.integer("3")).to eq(3)
      expect(described_class.integer(3)).to eq(3)
    end

    # The other half of the same bug: with a radix prefix honoured, malformed text became a
    # plausible number instead of an error.
    it "refuses the other radix prefixes rather than honouring them" do
      %w[0x1A 0b101 0o17].each do |prefixed|
        expect { described_class.integer(prefixed) }
          .to raise_error(Ksef::ValidationError, /Cannot read #{prefixed.inspect} as a whole number/)
      end
    end

    it "refuses a Float rather than truncating it" do
      expect { described_class.integer(2.9) }
        .to raise_error(Ksef::ValidationError, /Float is not allowed for a whole number/)
    end

    # `#to_i` would answer 0 here, turning a malformed document into a plausible one.
    it "refuses text that is not a number, rather than answering zero" do
      expect { described_class.integer("later") }
        .to raise_error(Ksef::ValidationError, /Cannot read "later" as a whole number/)
    end

    it "raises this gem's own error for nil, not a bare TypeError" do
      expect { described_class.integer(nil) }.to raise_error(Ksef::ValidationError, /Cannot read nil/)
    end
  end

  describe ".unflag" do
    it "reads the codes back as booleans" do
      expect(described_class.unflag("1")).to be(true)
      expect(described_class.unflag("2")).to be(false)
    end

    # An absent element means "no": the seller has no JST/GV elements at all, and a buyer
    # may omit them.
    it "treats an absent value as no" do
      expect(described_class.unflag(nil)).to be(false)
    end

    it "accepts booleans and integers, so it composes with .flag" do
      expect(described_class.unflag(described_class.flag(true))).to be(true)
      expect(described_class.unflag(1)).to be(true)
      expect(described_class.unflag(2)).to be(false)
      expect(described_class.unflag(false)).to be(false)
    end

    # A third value in a 1/2 field is a document we do not understand, not one to guess at.
    it "refuses anything else" do
      expect { described_class.unflag("3") }
        .to raise_error(Ksef::ValidationError, %r{Expected a 1/2 flag, got "3"})
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

  describe ".date_time on something that is not a time" do
    # The `else` branch asks for `#utc`. An object without one used to surface as a bare
    # NoMethodError from inside the serializer, outside this gem's hierarchy.
    it "raises this gem's own error rather than NoMethodError" do
      expect { described_class.date_time(123) }
        .to raise_error(Ksef::ValidationError, /Cannot read 123 as a timestamp/)
    end
  end

  describe ".date and .date_time" do
    it "formats a Date as ISO-8601" do
      expect(described_class.date(Date.new(2026, 8, 22))).to eq("2026-08-22")
    end

    it "parses a string date" do
      expect(described_class.date("2026-08-22")).to eq("2026-08-22")
    end

    # Date::Error is not part of this gem's hierarchy, so a caller rescuing Ksef::Error — which
    # is what the parser's docs tell them to do — would not catch a malformed P_1.
    it "wraps an unreadable date in a ValidationError" do
      ["not-a-date", "", "2026-13-45"].each do |text|
        expect { described_class.to_date(text) }
          .to raise_error(Ksef::ValidationError, /Cannot read .* as a date/)
      end
    end

    it "returns a Date untouched and coerces a Time" do
      date = Date.new(2026, 8, 22)

      expect(described_class.to_date(date)).to be(date)
      expect(described_class.to_date(Time.utc(2026, 8, 22, 5))).to eq(date)
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

  # `BigDecimal("NaN")` succeeds where `BigDecimal("abc")` raises, so these arrive through the
  # *String* door: a document stating `<P_11>NaN</P_11>` reached the model and serialised as
  # `NaN.00`. They also break the `==`/`hash` contract the negative-zero rule exists to hold —
  # `NaN != NaN`, so two identical lines compared unequal while hashing the same.
  describe "values that are not amounts" do
    it "refuses NaN, whichever door it comes through" do
      ["NaN", BigDecimal("NaN")].each do |value|
        expect { described_class.decimal(value) }
          .to raise_error(Ksef::ValidationError, /NaN is not a monetary or quantity value/)
      end
    end

    it "refuses Infinity" do
      expect { described_class.decimal(BigDecimal("Infinity")) }
        .to raise_error(Ksef::ValidationError, /Infinity is not a monetary or quantity value/)
    end

    it "reaches a document, which is why it is refused rather than merely discouraged" do
      source = File.read("spec/fixtures/fa3/golden/vat_single_line.xml", encoding: "UTF-8")
                   .sub(%r{<P_11>[^<]*</P_11>}, "<P_11>NaN</P_11>")

      expect { Ksef::FA3.parse(source) }.to raise_error(Ksef::ValidationError, /NaN is not/)
    end
  end

  # A string can be *invalid* — bytes that decode as nothing — or *validly encoded in
  # something that is not UTF-8*. `valid_encoding?` answers true for the second, so a
  # Windows-1250 name (what a Polish ERP emits) passed every guard and then raised
  # `Encoding::CompatibilityError` out of `#errors`, `#to_xml` and `Client#send_invoice`.
  describe "encodings that are valid but are not UTF-8" do
    it "accepts UTF-8, and ASCII or valid UTF-8 bytes tagged binary" do
      expect(Ksef::FA3::FieldChecks).to be_utf8("Łódź")
      expect(Ksef::FA3::FieldChecks).to be_utf8("plain".b)
      expect(Ksef::FA3::FieldChecks).to be_utf8(File.binread("spec/fixtures/fa3/golden/vat_single_line.xml"))
    end

    it "refuses a named non-UTF-8 encoding, and invalid bytes" do
      expect(Ksef::FA3::FieldChecks).not_to be_utf8("Łódź".encode("Windows-1250"))
      expect(Ksef::FA3::FieldChecks).not_to be_utf8("Łódź".encode("ISO-8859-2"))
      expect(Ksef::FA3::FieldChecks).not_to be_utf8((+"Consul\xFFting").force_encoding("UTF-8"))
    end

    it "leaves such a value alone rather than collapsing it, so it survives to be reported" do
      windows = "Łódź".encode("Windows-1250")

      expect(described_class.text(windows)).to equal(windows)
    end
  end
end
