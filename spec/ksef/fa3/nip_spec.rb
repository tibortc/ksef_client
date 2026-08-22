# frozen_string_literal: true

RSpec.describe Ksef::FA3::NIP do
  # Weights and rule from DESIGN.md §7.2.
  it "accepts the checksum-valid NIPs used across the docs and fixtures" do
    %w[7762811692 7980332920 3755747347 9999999999 1111111111].each do |nip|
      expect(described_class.valid?(nip)).to be(true), "expected #{nip} to be valid"
    end
  end

  it "rejects a single mistyped digit" do
    expect(described_class.valid?("9999999998")).to be(false)
  end

  it "normalises the forms a NIP actually arrives in" do
    expect(described_class.normalize("PL 977-742-77-32")).to eq("9777427732")
    expect(described_class.normalize("977-742-77-32")).to eq("9777427732")
  end

  it "validates a NIP written with separators or a country prefix" do
    expect(described_class.valid?("PL9999999999")).to be(true)
    expect(described_class.valid?("999-999-99-99")).to be(true)
  end

  it "rejects the wrong number of digits" do
    expect(described_class.valid?("999999999")).to be(false)
    expect(described_class.valid?("99999999999")).to be(false)
  end

  it "rejects non-digits" do
    expect(described_class.valid?("999999999X")).to be(false)
  end

  describe ".validate!" do
    it "says how many digits it got, not just that it failed" do
      expect { described_class.validate!("12345") }
        .to raise_error(Ksef::ValidationError, /must be 10 digits.*5 digit/m)
    end

    it "names the expected check digit" do
      expect { described_class.validate!("9999999998") }
        .to raise_error(Ksef::ValidationError, /expected 9, got 8/)
    end

    it "uses the supplied field name, so the caller knows which party is wrong" do
      expect { described_class.validate!("12345", field: "buyer NIP") }
        .to raise_error(Ksef::ValidationError, /buyer NIP/)
    end

    it "returns the normalised digits on success" do
      expect(described_class.validate!("PL999-999-99-99")).to eq("9999999999")
    end
  end
end
