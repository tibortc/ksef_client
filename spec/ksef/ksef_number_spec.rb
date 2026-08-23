# frozen_string_literal: true

RSpec.describe Ksef::KsefNumber do
  # The Ministry's own documented example (docs/REFERENCE.md §13), which doubles as the
  # golden vector for the CRC-8 implementation.
  let(:documented) { "5265877635-20250826-0100001AF629-AF" }

  describe ".parse" do
    subject(:number) { described_class.parse(documented) }

    it "accepts upstream's documented example" do
      expect(number.to_s).to eq(documented)
    end

    it "splits out the seller NIP and the technical part" do
      expect(number.nip).to eq("5265877635")
      expect(number.technical).to eq("0100001AF629")
      expect(number.checksum).to eq("AF")
    end

    # Not metadata: per limity-api.md this is the invoice's official receipt date, which is
    # why it is a Date rather than eight characters.
    it "parses the acceptance date, which is the official receipt date" do
      expect(number.assigned_on).to eq(Date.new(2025, 8, 26))
    end

    it "is exactly 35 characters" do
      expect(number.to_s.length).to eq(described_class::LENGTH)
    end

    it "compares by value" do
      expect(described_class.parse(documented)).to eq(described_class.parse(documented.dup))
    end
  end

  describe "the CRC-8 checksum" do
    # Polynomial 0x07, init 0x00, no reflection, no final XOR, over the first 32 characters.
    it "reproduces the documented checksum" do
      expect(described_class.crc8("5265877635-20250826-0100001AF629")).to eq(0xAF)
      expect(described_class.checksum_for(documented)).to eq("AF")
    end

    it "computes over the first 32 characters, so the full number and its body agree" do
      expect(described_class.checksum_for(documented))
        .to eq(described_class.checksum_for("5265877635-20250826-0100001AF629"))
    end

    it "starts from zero, so an empty input is zero" do
      expect(described_class.crc8("")).to eq(0)
    end

    # The reason to check locally at all: these are the slips that happen when a number is
    # copied between systems or read down a telephone.
    it "catches a single mistyped character" do
      expect { described_class.parse("5265877635-20250826-0100001AF628-AF") }
        .to raise_error(Ksef::ValidationError, /CRC-8 mismatch/)
    end

    it "catches a transposition" do
      expect { described_class.parse("5265877635-20250826-0100001AF692-AF") }
        .to raise_error(Ksef::ValidationError, /checksum AF/)
    end

    it "names both the carried and the computed checksum, so the error is actionable" do
      expect { described_class.parse("5265877635-20250826-0100001AF629-00") }
        .to raise_error(Ksef::ValidationError, /checksum 00, but its first 32 characters give AF/)
    end
  end

  describe "rejections" do
    it "refuses lowercase hex, which the format does not permit" do
      expect { described_class.parse("5265877635-20250826-0100001af629-AF") }
        .to raise_error(Ksef::ValidationError, /malformed/)
    end

    it "refuses the wrong length and says what it got" do
      expect { described_class.parse("5265877635-20250826-0100001AF629") }
        .to raise_error(Ksef::ValidationError, /32 characters, expected 35/)
    end

    it "refuses a NIP that is not ten digits" do
      expect { described_class.parse("526587763-20250826-0100001AF629-AF") }
        .to raise_error(Ksef::ValidationError, /malformed/)
    end

    it "refuses nil and empty without raising something other than ValidationError" do
      expect { described_class.parse(nil) }.to raise_error(Ksef::ValidationError)
      expect { described_class.parse("") }.to raise_error(Ksef::ValidationError)
    end

    # 30 February passes the \d{8} pattern but is not a date. Caught separately so the
    # message says which part is wrong.
    it "refuses an impossible date even though it matches the digit pattern" do
      body = "5265877635-20250230-0100001AF629"
      expect { described_class.parse("#{body}-#{described_class.checksum_for(body)}") }
        .to raise_error(Ksef::ValidationError, /not a real date/)
    end
  end

  # §13.1. The contract declares minLength 35 / maxLength 36 and an optional hyphen splitting
  # the technical part 6-6, for KSeF 1.0 backward compatibility. This gem enforced 35 until
  # 2026-08-23, which made legacy numbers unlookupable — `download_invoice` and
  # `for_ksef_number` both parse before use, so it failed locally where the API answers 200.
  describe "the 36-character legacy form" do
    subject(:legacy) { described_class.parse("5265877635-20250826-010000-1AF629-AF") }

    it "is accepted" do
      expect(legacy.value.length).to eq(36)
      expect(legacy).to be_legacy
    end

    it "normalises the technical part, so both forms agree" do
      expect(legacy.technical).to eq(described_class.parse(documented).technical)
      expect(legacy.nip).to eq("5265877635")
      expect(legacy.assigned_on).to eq(Date.new(2025, 8, 26))
    end

    # The CRC input rule for this form is unverified — §13's "first 32 characters" describes
    # the 35-character layout. Accepting without vouching beats guessing and rejecting a
    # number the API would honour.
    it "is not checksum-verified, and says so" do
      expect(legacy.checksum_verified?).to be(false)
    end

    it "is accepted even with a checksum the 35-char rule would reject" do
      expect { described_class.parse("5265877635-20250826-010000-1AF629-00") }.not_to raise_error
    end

    it "still rejects a malformed legacy number" do
      expect { described_class.parse("5265877635-20250826-01000-01AF629-AF") }
        .to raise_error(Ksef::ValidationError, /malformed/)
    end

    it "names both accepted lengths when it rejects" do
      expect { described_class.parse("nonsense") }
        .to raise_error(Ksef::ValidationError, /expected 35 or 36/)
    end
  end

  it "reports the 2.0 form as checksum-verified" do
    expect(described_class.parse(documented).checksum_verified?).to be(true)
    expect(described_class.parse(documented)).not_to be_legacy
  end

  describe ".valid?" do
    it "is true for the documented example" do
      expect(described_class).to be_valid(documented)
    end

    it "is false rather than raising for anything malformed" do
      expect(described_class.valid?("nonsense")).to be(false)
      expect(described_class.valid?("5265877635-20250826-0100001AF629-00")).to be(false)
    end
  end

  # Lets a parsed number be used wherever the raw string was expected, which is most places
  # — it is a lookup key for `GET /invoices/ksef/{ksefNumber}`.
  it "interpolates and joins as its string form" do
    expect("invoices/ksef/#{described_class.parse(documented)}")
      .to eq("invoices/ksef/#{documented}")
    expect(File.join("x", described_class.parse(documented))).to end_with(documented)
  end
end
