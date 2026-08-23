# frozen_string_literal: true

RSpec.describe Ksef::Auth::Challenge do
  it "stringifies to the challenge value, for dropping into the request document" do
    challenge = described_class.from({ "challenge" => "20250604-CR-461EA5B000-537A6BA15D-D7" })

    expect(challenge.to_s).to eq("20250604-CR-461EA5B000-537A6BA15D-D7")
  end

  it "has no expiry when the server sent no timestamp" do
    expect(described_class.from({ "challenge" => "c" }).expires_at).to be_nil
  end

  # The format lives here rather than on either request document because both
  # authentication methods consume the same challenge (§4.1).
  describe ".validate_format!" do
    it "accepts upstream's own documented example" do
      expect(described_class.validate_format!("20250604-CR-461EA5B000-537A6BA15D-D7"))
        .to eq("20250604-CR-461EA5B000-537A6BA15D-D7")
    end

    it "requires the literal CR kind tag and uppercase hex" do
      expect { described_class.validate_format!("20250604-XX-461EA5B000-537A6BA15D-D7") }
        .to raise_error(Ksef::ValidationError)
      expect { described_class.validate_format!("20250604-CR-461ea5b000-537A6BA15D-D7") }
        .to raise_error(Ksef::ValidationError)
    end

    it "rejects a non-String, so a Challenge object cannot be passed by mistake" do
      expect { described_class.validate_format!(described_class.from({ "challenge" => "c" })) }
        .to raise_error(Ksef::ValidationError, /is malformed/)
    end
  end
end
