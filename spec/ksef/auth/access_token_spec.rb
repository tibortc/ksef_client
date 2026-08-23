# frozen_string_literal: true

RSpec.describe Ksef::Auth::AccessToken do
  subject(:credential) { described_class.new(tokens, client: client, clock: -> { now }) }

  let(:issued) { Time.utc(2026, 8, 23, 12, 0, 0) }
  let(:now) { issued }

  # A fifteen-minute access token and a seven-day refresh token, which is the shape §4.2
  # describes ("kilkanaście minut" and up to 7 days).
  let(:tokens) do
    Ksef::Auth::Tokens.from(
      "accessToken" => { "token" => "access.one", "validUntil" => (issued + 900).iso8601 },
      "refreshToken" => { "token" => "refresh.jwt", "validUntil" => (issued + (7 * 86_400)).iso8601 }
    )
  end

  let(:client) { instance_double(Ksef::Auth::Client) }

  def fresh_info(name, valid_for)
    Ksef::Auth::TokenInfo.from("token" => name, "validUntil" => (now + valid_for).iso8601)
  end

  describe "#bearer" do
    it "returns the access token while it is fresh, without calling the API" do
      allow(client).to receive(:refresh)

      expect(credential.bearer).to eq("access.one")
      expect(client).not_to have_received(:refresh)
    end

    # 80% of a 900-second life is 720 seconds. The clock is a mutable local rather than a
    # second construction, because the lifetime is measured from when the token was taken
    # delivery of — constructing at a later moment moves the threshold with it.
    it "refreshes once past 80% of the observed lifetime" do
      moment = issued
      allow(client).to receive(:refresh).with(refresh_token: "refresh.jwt") do
        Ksef::Auth::TokenInfo.from("token" => "access.two", "validUntil" => (moment + 900).iso8601)
      end
      credential = described_class.new(tokens, client: client, clock: -> { moment })

      expect(credential.bearer).to eq("access.one")
      moment += 721
      expect(credential.bearer).to eq("access.two")
    end

    it "does not refresh a moment before the threshold" do
      moment = issued
      credential = described_class.new(tokens, client: client, clock: -> { moment })
      moment += 719
      allow(client).to receive(:refresh)

      expect(credential.bearer).to eq("access.one")
      expect(client).not_to have_received(:refresh)
    end
  end

  describe "#stale?" do
    it "is false when fresh and true past the threshold" do
      expect(credential.stale?(issued + 719)).to be(false)
      expect(credential.stale?(issued + 720)).to be(true)
    end

    # A validUntil we could not parse is no reason to spend a refresh; a genuinely dead
    # token still surfaces as a 401 from the API.
    it "is false when the lifetime cannot be established" do
      undated = Ksef::Auth::Tokens.from(
        "accessToken" => { "token" => "access.one", "validUntil" => "not a date" },
        "refreshToken" => { "token" => "refresh.jwt" }
      )

      expect(described_class.new(undated, client: client, clock: -> { now }).stale?).to be(false)
    end

    # Delivered already-expired: treat as stale immediately rather than computing a
    # threshold in the past.
    it "is true immediately for a token that arrived already expired" do
      stale = Ksef::Auth::Tokens.from(
        "accessToken" => { "token" => "access.one", "validUntil" => (issued - 60).iso8601 },
        "refreshToken" => { "token" => "refresh.jwt", "validUntil" => (issued + 86_400).iso8601 }
      )

      expect(described_class.new(stale, client: client, clock: -> { now }).stale?).to be(true)
    end
  end

  describe "#refresh!" do
    it "renews unconditionally and uses the new token afterwards" do
      allow(client).to receive(:refresh)
        .with(refresh_token: "refresh.jwt").and_return(fresh_info("access.two", 900))

      expect(credential.refresh!.bearer).to eq("access.two")
    end

    it "presents the refresh token, not the access token" do
      allow(client).to receive(:refresh).and_return(fresh_info("access.two", 900))
      credential.refresh!

      expect(client).to have_received(:refresh).with(refresh_token: "refresh.jwt")
    end

    # Once the refresh token lapses there is no way back but a full re-authentication, and
    # saying so beats a bare 401 from the API.
    it "refuses when the refresh token has itself expired, and says what to do" do
      lapsed = Ksef::Auth::Tokens.from(
        "accessToken" => { "token" => "access.one", "validUntil" => (issued - 1).iso8601 },
        "refreshToken" => { "token" => "refresh.jwt", "validUntil" => (issued - 1).iso8601 }
      )

      expect { described_class.new(lapsed, client: client, clock: -> { now }).refresh! }
        .to raise_error(Ksef::AuthenticationError, /Re-authenticate from the challenge/)
    end
  end

  describe "thread safety" do
    # DESIGN.md §5.2. The staleness check is re-run inside the lock, so a burst of threads
    # produces one refresh rather than one per thread.
    it "refreshes once when many threads find the token stale together" do
      calls = 0
      allow(client).to receive(:refresh) do
        calls += 1
        fresh_info("access.two", 900)
      end
      moment = issued
      shared = described_class.new(tokens, client: client, clock: -> { moment })
      moment += 800

      results = Array.new(8) { Thread.new { shared.bearer } }.map(&:value)

      expect(results.uniq).to eq(["access.two"])
      expect(calls).to eq(1)
    end
  end

  describe "redaction" do
    it "keeps both tokens out of #to_s and #inspect" do
      expect(credential.to_s).to eq("[REDACTED]")
      expect(credential.inspect).not_to include("access.one")
      expect(credential.inspect).not_to include("refresh.jwt")
    end

    it "still shows expiry and staleness, which is what makes the redacted form useful" do
      expect(credential.inspect).to include("stale=false")
      expect(credential.inspect).to include("2026-08-23")
    end
  end

  it "reports the access token's expiry and its own expiry state" do
    expect(credential.valid_until).to eq(issued + 900)
    expect(credential.expired?(issued + 899)).to be(false)
    expect(credential.expired?(issued + 901)).to be(true)
  end

  it "reports when the refresh token has expired" do
    expect(credential.refresh_token_expired?).to be(false)
    expect(credential.refresh_token_expired?(issued + (8 * 86_400))).to be(true)
  end

  # `TokenInfo.from(nil)` returns nil, so a redeem response missing either token yields a
  # pair holding none — a reachable state, not a hypothetical one. Worth its own block
  # because the first version of this class turned it into a `NoMethodError` on nil from
  # deep inside `#bearer`, which tells a caller nothing about what went wrong.
  describe "a redeem response that carried no tokens" do
    subject(:tokenless) { described_class.new(Ksef::Auth::Tokens.from({}), client: client, clock: -> { now }) }

    it "reports itself expired rather than claiming validity it cannot have" do
      expect(tokenless.expired?).to be(true)
      expect(tokenless.valid_until).to be_nil
    end

    # Not stale — staleness is a statement about a lifetime, and there is no lifetime here.
    # `#bearer` handles the absence directly instead.
    it "is not stale, because there is no lifetime to be past 80% of" do
      expect(tokenless.stale?).to be(false)
    end

    it "raises a clear AuthenticationError from #bearer, not a NoMethodError" do
      expect { tokenless.bearer }
        .to raise_error(Ksef::AuthenticationError, /Re-authenticate from the challenge/)
    end

    it "says the refresh token is expired, since a missing one can never be used" do
      expect(tokenless.refresh_token_expired?).to be(true)
    end
  end
end
