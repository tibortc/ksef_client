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

  # Buckets pair a current rate with the one it replaced. Getting this wrong is invisible to
  # the XSD: a mis-bucketed amount still validates, it just declares the wrong kind of tax.
  describe "the current/historical rate pairs" do
    it "puts 23 and 22 in bucket one, 8 and 7 in bucket two" do
      expect(described_class.bucket("23")).to eq(described_class.bucket("22"))
      expect(described_class.bucket("8")).to eq(described_class.bucket("7"))
    end

    # `"3"` used to map to bucket *five*, which is not a rate bucket at all: `P_14_5` is
    # "kwota podatku od wartości dodanej" — foreign VAT under the OSS procedure of dział XII
    # rozdział 6a — so a domestic 3% sale was declared as OSS foreign VAT (§8.1a).
    it "puts 4 and 3 in bucket four, the passenger-taxi flat rate" do
      expect(described_class.bucket("4")).to eq(%w[P_13_4 P_14_4])
      expect(described_class.bucket("3")).to eq(%w[P_13_4 P_14_4])
    end

    # OSS lines carry their rate in `P_12_XII`, a percentage, not as a `P_12` code — so no
    # rate code reaching this table should ever select bucket five.
    # Bucket 5 is the OSS special procedure (per-line rate in `P_12_XII`) and `P_13_11` the
    # margin scheme (declared through `Adnotacje/PMarzy`). Neither is reachable from a `P_12`
    # code — but `P_13_9` was on this list too, by accident, because `np II` was pointed at
    # `P_13_8`. An incomplete list here reads as a deliberate gap, which is how that survived.
    it "names every summary element no rate code can reach, and no more" do
      expect(described_class::BUCKETS.values.flatten).not_to include(*described_class.unreachable_elements)
      expect(described_class.unreachable_elements).to eq(%w[P_13_5 P_14_5 P_13_11])
    end

    it "reaches every other net bucket the schema defines" do
      reachable = described_class::BUCKETS.values.map(&:first).uniq
      all_net = Ksef::FA3::Totals::NET_ELEMENTS

      expect(all_net - reachable - described_class.unreachable_elements).to be_empty
    end

    it "still maps every code the schema defines" do
      expect(described_class.unmapped_codes).to be_empty
    end
  end
end
