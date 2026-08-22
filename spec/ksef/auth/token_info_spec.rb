# frozen_string_literal: true

RSpec.describe Ksef::Auth::TokenInfo do
  subject(:info) { described_class.from({ "token" => "header.payload.signature", "validUntil" => expiry }) }

  let(:expiry) { "2026-08-22T12:00:00Z" }

  it "parses the JWT and its expiry" do
    expect(info.token).to eq("header.payload.signature")
    expect(info.valid_until).to eq(Time.utc(2026, 8, 22, 12))
  end

  it "is nil for an absent payload, so an optional token does not become an empty object" do
    expect(described_class.from(nil)).to be_nil
  end

  # DESIGN.md §4.5. `#to_s` is redacted as well as `#inspect`, because the leak that
  # actually happens is someone interpolating a token into a log line.
  describe "redaction" do
    it "redacts #inspect" do
      expect(info.inspect).to include("[REDACTED]")
      expect(info.inspect).not_to include("header.payload.signature")
    end

    it "redacts #to_s" do
      expect(info.to_s).to eq("[REDACTED]")
    end

    it "does not leak through interpolation" do
      expect("Authorization: Bearer #{info}").not_to include("header.payload.signature")
    end

    it "keeps the expiry visible, which is diagnostic rather than secret" do
      expect(info.inspect).to include("2026-08-22 12:00:00 UTC")
    end

    it "still yields the value to an explicit reader" do
      expect(info.token).to eq("header.payload.signature")
    end
  end

  describe "#expired?" do
    it "is false before the expiry" do
      expect(info.expired?(Time.utc(2026, 8, 22, 11, 59))).to be(false)
    end

    it "is true at the expiry, not merely after it" do
      expect(info.expired?(Time.utc(2026, 8, 22, 12))).to be(true)
    end

    context "when the server sent no expiry" do
      let(:expiry) { nil }

      it "is never considered expired, rather than treated as long past" do
        expect(info.expired?).to be(false)
      end
    end
  end
end
