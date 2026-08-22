# frozen_string_literal: true

RSpec.describe Ksef::Auth::Tokens do
  def build(access_until:)
    described_class.from({ "accessToken" => { "token" => "a", "validUntil" => access_until },
                           "refreshToken" => { "token" => "r", "validUntil" => nil } })
  end

  it "reads both tokens" do
    tokens = build(access_until: "2026-08-22T12:00:00Z")

    expect(tokens.access_token.token).to eq("a")
    expect(tokens.refresh_token.token).to eq("r")
  end

  it "reports expiry from the access token" do
    tokens = build(access_until: "2026-08-22T12:00:00Z")

    expect(tokens.expired?(Time.utc(2026, 8, 22, 11))).to be(false)
    expect(tokens.expired?(Time.utc(2026, 8, 22, 13))).to be(true)
  end

  it "treats a missing access token as expired rather than usable" do
    expect(described_class.from({}).expired?).to be(true)
  end
end
