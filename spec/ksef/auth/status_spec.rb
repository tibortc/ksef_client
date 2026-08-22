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
end
