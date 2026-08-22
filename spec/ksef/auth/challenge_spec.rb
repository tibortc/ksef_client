# frozen_string_literal: true

RSpec.describe Ksef::Auth::Challenge do
  it "stringifies to the challenge value, for dropping into the request document" do
    challenge = described_class.from({ "challenge" => "20250604-CR-461EA5B000-537A6BA15D-D7" })

    expect(challenge.to_s).to eq("20250604-CR-461EA5B000-537A6BA15D-D7")
  end

  it "has no expiry when the server sent no timestamp" do
    expect(described_class.from({ "challenge" => "c" }).expires_at).to be_nil
  end
end
