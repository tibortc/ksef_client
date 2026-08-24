# frozen_string_literal: true

RSpec.describe Ksef::FA3::Address do
  it "composes structured parts into AdresL1" do
    address = described_class.new(street: "Prosta 1", city: "Warszawa", postal_code: "00-001")
    expect(address.to_fa3).to eq("KodKraju" => "PL", "AdresL1" => "Prosta 1, 00-001 Warszawa")
  end

  it "accepts a pre-formatted line for callers who already have one" do
    expect(described_class.new(line1: "Prosta 1, 00-001 Warszawa").to_fa3["AdresL1"])
      .to eq("Prosta 1, 00-001 Warszawa")
  end

  it "includes AdresL2 only when given" do
    expect(described_class.new(line1: "a").to_fa3).not_to have_key("AdresL2")
    expect(described_class.new(line1: "a", line2: "b").to_fa3["AdresL2"]).to eq("b")
  end

  it "defaults the country to PL" do
    expect(described_class.new(line1: "a").country).to eq("PL")
  end

  # At construction, not at serialisation: `AdresL1` is mandatory in `TAdres`, so an address
  # without one is not a thing that can later become valid.
  it "raises when there is nothing to compose" do
    expect { described_class.new(country: "PL") }
      .to raise_error(Ksef::ValidationError, /needs either line1/)
  end

  describe "not retaining the structured parts" do
    # FA(3) has no structured address, and neither does the one official FA(3) reader
    # (docs/REFERENCE.md §8.2b). The parts compose on the way in and are not state, which is
    # what lets a parsed address equal the built one it came from.
    it "holds only what the document holds" do
      expect(described_class.members).to eq(%i[line1 line2 country])
    end

    it "equals the same address given as a formatted line" do
      from_parts = described_class.new(street: "Prosta 1", city: "Warszawa", postal_code: "00-001")
      from_line = described_class.new(line1: "Prosta 1, 00-001 Warszawa")

      expect(from_parts).to eq(from_line)
      expect(from_parts.hash).to eq(from_line.hash)
    end

    it "still distinguishes addresses that differ in the document" do
      expect(described_class.new(line1: "Prosta 1")).not_to eq(described_class.new(line1: "Prosta 2"))
      expect(described_class.new(line1: "a", country: "PL")).not_to eq(described_class.new(line1: "a", country: "DE"))
    end
  end

  describe "composing" do
    it "skips absent parts rather than leaving punctuation behind" do
      expect(described_class.new(street: "Prosta 1").line1).to eq("Prosta 1")
      expect(described_class.new(city: "Warszawa", postal_code: "00-001").line1).to eq("00-001 Warszawa")
      expect(described_class.new(city: "Warszawa").line1).to eq("Warszawa")
    end

    it "prefers an explicit line1 over the parts" do
      address = described_class.new(line1: "Given", street: "Ignored", city: "Ignored")

      expect(address.line1).to eq("Given")
    end
  end

  describe "#with" do
    # Data#with skips a custom initialize on Ruby 3.2 (see FA3::Canonical), which would have
    # let a copy exist with no AdresL1 at all.
    it "re-runs the constructor, so the mandatory line is still enforced" do
      expect { described_class.new(line1: "Prosta 1").with(line1: nil) }
        .to raise_error(Ksef::ValidationError, /needs either line1/)
    end
  end
end
