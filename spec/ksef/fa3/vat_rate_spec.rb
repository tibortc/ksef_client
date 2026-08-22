# frozen_string_literal: true

RSpec.describe Ksef::FA3::VatRate do
  # The bucket mapping is read from the XSD's documentation, recorded in
  # docs/REFERENCE.md §8.1a. It is not "rates in descending order" — bucket 4 is the
  # passenger-taxi flat rate and bucket 5 a special procedure.
  it "maps the standard rate to bucket 1" do
    expect(described_class.bucket("23")).to eq(%w[P_13_1 P_14_1])
    expect(described_class.bucket("22")).to eq(%w[P_13_1 P_14_1])
  end

  it "maps both reduced rates to their own buckets" do
    expect(described_class.bucket("8")).to eq(%w[P_13_2 P_14_2])
    expect(described_class.bucket("5")).to eq(%w[P_13_3 P_14_3])
  end

  it "gives the three zero rates distinct buckets, none with a tax element" do
    expect(described_class.bucket("0 KR")).to eq(["P_13_6_1", nil])
    expect(described_class.bucket("0 WDT")).to eq(["P_13_6_2", nil])
    expect(described_class.bucket("0 EX")).to eq(["P_13_6_3", nil])
  end

  it "maps exempt and reverse-charge codes without a tax element" do
    expect(described_class.bucket("zw")).to eq(["P_13_7", nil])
    expect(described_class.bucket("oo")).to eq(["P_13_10", nil])
  end

  it "raises for a code the schema does not define" do
    expect { described_class.bucket("19") }
      .to raise_error(Ksef::ValidationError, /Unknown VAT rate code "19"/)
  end

  # A schema revision that adds or renames a rate code should surface here rather than
  # as a KSeF rejection.
  it "has a bucket for every code the generated enum knows" do
    expect(described_class.unmapped_codes).to be_empty
  end

  it "reports a percentage only for the numeric codes" do
    expect(described_class.percentage("23")).to eq(23)
    expect(described_class.percentage("zw")).to be_nil
    expect(described_class.percentage("0 WDT")).to be_nil
  end
end
