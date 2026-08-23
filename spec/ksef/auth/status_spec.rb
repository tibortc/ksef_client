# frozen_string_literal: true

RSpec.describe Ksef::Auth::Status do
  # 550 is the system cancelling its own work and inviting a retry, which is a different
  # proposition from a rejected certificate — the caller can sensibly start over.
  it "treats only the system-cancelled code as retryable" do
    expect(described_class.retryable?(described_class::CANCELLED)).to be(true)
    expect(described_class.retryable?(described_class::CERTIFICATE_ERROR)).to be(false)
  end

  it "describes an unrecognised code rather than returning nil" do
    expect(described_class.describe(1234)).to eq("unrecognised status code 1234")
  end

  # 480 was missing until 2026-08-23: the ledger had sourced the table from the C# client's
  # enum, which does not carry it, when the pinned contract states the full list. It is the
  # one code whose right response is neither a retry nor a fix on our side.
  describe "480 — authentication blocked" do
    it "is terminal and not retryable" do
      expect(described_class.terminal?(described_class::BLOCKED)).to be(true)
      expect(described_class.retryable?(described_class::BLOCKED)).to be(false)
    end

    it "tells the caller to contact the Ministry rather than try again" do
      expect(described_class.describe(described_class::BLOCKED))
        .to include("security incident", "do not retry")
    end
  end

  # The contract's table is the source of record (docs/REFERENCE.md §4.8). Asserted so a
  # code added upstream shows up here rather than as "unrecognised" at runtime.
  it "describes every code the pinned contract declares" do
    contract_codes = [100, 200, 415, 425, 450, 460, 470, 480, 500, 550]

    expect(contract_codes.reject { |code| described_class::DESCRIPTIONS.key?(code) }).to be_empty
  end
end
