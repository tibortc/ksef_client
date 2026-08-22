# frozen_string_literal: true

RSpec.describe Ksef::Auth do
  describe ".time" do
    it "parses the contract's date-time format" do
      expect(described_class.time("2026-08-22T10:00:00Z")).to eq(Time.utc(2026, 8, 22, 10))
    end

    it "keeps a non-UTC offset rather than silently shifting it" do
      expect(described_class.time("2026-08-22T10:00:00+02:00").utc).to eq(Time.utc(2026, 8, 22, 8))
    end

    it "passes a Time through untouched" do
      now = Time.utc(2026, 8, 22)

      expect(described_class.time(now)).to be(now)
    end

    it "returns nil for an absent value" do
      expect(described_class.time(nil)).to be_nil
      expect(described_class.time("")).to be_nil
    end

    # These fields are informational — expiry hints, start times. Failing an authentication
    # that otherwise succeeded because the server sent an odd timestamp would be perverse.
    it "returns nil rather than raising on an unparseable value" do
      expect(described_class.time("yesterday afternoon")).to be_nil
    end
  end

  describe "NAMESPACES" do
    it "defaults to 2.0, which is what both official clients emit (§14.4)" do
      expect(described_class::NAMESPACES.fetch(described_class::DEFAULT_SCHEMA_VERSION))
        .to eq("http://ksef.mf.gov.pl/auth/token/2.0")
    end
  end
end
