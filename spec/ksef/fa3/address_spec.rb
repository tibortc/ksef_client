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

  it "raises when there is nothing to compose" do
    expect { described_class.new(country: "PL").to_fa3 }
      .to raise_error(Ksef::ValidationError, /needs either line1/)
  end
end
