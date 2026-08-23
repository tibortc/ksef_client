# frozen_string_literal: true

RSpec.describe Ksef::Sessions::UpoPage do
  subject(:page) { described_class.from(payload) }

  let(:payload) do
    { "referenceNumber" => "20260823-EU-1234567890-1234567890-AB",
      "downloadUrl" => "https://ksefstorage.blob.core.windows.net/upo/abc?sig=SECRETSIGNATURE",
      "downloadUrlExpirationDate" => "2026-08-23T13:00:00Z" }
  end

  describe ".from" do
    it "maps the three fields of the contract's UpoPageResponse" do
      expect(page.reference_number).to eq("20260823-EU-1234567890-1234567890-AB")
      expect(page.download_url).to end_with("sig=SECRETSIGNATURE")
      expect(page.expires_at).to eq(Time.utc(2026, 8, 23, 13))
    end

    it "tolerates a missing expiry rather than raising" do
      expect(described_class.from({}).expires_at).to be_nil
    end
  end

  describe "#expired?" do
    it "is false before the expiry and true after" do
      expect(page.expired?(Time.utc(2026, 8, 23, 12, 59))).to be(false)
      expect(page.expired?(Time.utc(2026, 8, 23, 13, 1))).to be(true)
    end

    # No expiry means nothing to compare against; the metered API route is the fallback
    # either way, so guessing "expired" would discard a link that may still work.
    it "is false when no expiry was given" do
      expect(described_class.from({})).not_to be_expired
    end
  end

  # The URL carries its own authorisation in the query string, so it is a credential. §14.2
  # is explicit that it must never be logged or persisted as a durable reference — it is
  # regenerated on every status query.
  describe "keeping the pre-signed URL out of logs" do
    it "does not put the URL in #inspect" do
      expect(page.inspect).not_to include("SECRETSIGNATURE")
      expect(page.inspect).to include("[PRE-SIGNED]")
    end

    it "stringifies to the reference number, not the link" do
      expect(page.to_s).to eq("20260823-EU-1234567890-1234567890-AB")
      expect("page=#{page}").not_to include("SECRETSIGNATURE")
    end

    # Still reachable deliberately — the whole point is to follow it.
    it "still exposes the URL to a caller that asks for it" do
      expect(page.download_url).to include("SECRETSIGNATURE")
    end

    it "keeps the reference number visible, which is what makes the redacted form useful" do
      expect(page.inspect).to include("20260823-EU-1234567890-1234567890-AB")
    end
  end
end
