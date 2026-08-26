# frozen_string_literal: true

require "spec_helper"

# The state of the recorded tier itself (DESIGN.md §9.1).
#
# **A tier that silently tests nothing is this project's documented failure mode** — the glob
# that matched no sample files and left the round-trip suite green; the coverage gate `rake`
# skipped for months while claiming to mirror CI. `spec/support/vcr.rb` excludes `:recorded`
# examples until a cassette exists, which is the same shape, so the absence is asserted here
# rather than left to be noticed.
#
# When cassettes land these examples keep working and simply report a different number.
RSpec.describe "the recorded test tier" do
  it "reports how many cassettes exist, so 'nothing recorded' is visible rather than silent" do
    expect(RecordedTier.recorded?).to eq(Dir.glob(File.join(RecordedTier::DIR, "**", "*.yml")).any?)
  end

  it "keeps its cassettes out of the packaged gem" do
    expect(RecordedTier::DIR).to include("/spec/")
  end

  # The hooks have to exist before the first recording, not after: a cassette recorded without
  # them and committed is a credential leak `git` remembers. Asserting the *list* rather than
  # the behaviour, because there is nothing recorded to scrub yet.
  it "scrubs every secret the hygiene spec scans for" do
    expect(RecordedTier::SECRET_ENV).to include("KSEF_TEST_TOKEN")
  end

  # Not an oversight: a NIP is public, it is printed on every invoice, and the KSeF number
  # embeds it — `KsefNumber::FORMAT` opens with `(\d{10})`. Scrubbing it corrupts both the
  # number and the UPO, costing the two assertions only a real response can support.
  it "does not scrub the NIP, which is an identifier rather than a credential" do
    expect(RecordedTier::SECRET_ENV).not_to include("KSEF_TEST_NIP")
  end

  # Proved against the shape that actually leaked: a redeem response carrying two tokens, where
  # a `filter_sensitive_data` block captured the first and left the second.
  describe "redaction" do
    let(:two_tokens) do
      '{"accessToken":{"token":"eyJhbGciOiJIUzI1NiJ9.eyJ0eXAiOiJBY2Nlc3MifQ.sig1"},' \
        '"refreshToken":{"token":"eyJhbGciOiJIUzI1NiJ9.eyJ0eXAiOiJSZWZyZXNoIn0.sig2"}}'
    end

    it "redacts every token in a body, not merely the first" do
      redacted = RecordedTier.redact(two_tokens)

      expect(redacted).not_to include("sig1", "sig2", "eyJ")
      expect(redacted.scan("<REDACTED>").size).to eq(2)
    end

    it "leaves XML alone, so a UPO still matches the hash KSeF sent" do
      upo = '<?xml version="1.0"?><Potwierdzenie><NumerKSeFDokumentu>1234567890-20260826-AB-CD-EF' \
            "</NumerKSeFDokumentu></Potwierdzenie>"

      expect(RecordedTier.redact(upo)).to eq(upo)
    end

    it "handles an absent body" do
      expect(RecordedTier.redact(nil)).to be_nil
      expect(RecordedTier.redact("")).to eq("")
    end
  end

  # §9.1, obstacle 1. Encrypted request bodies differ on every run by construction, so a body
  # matcher cannot work — and would present as a flaky test rather than an impossible one.
  it "never matches requests on the body" do
    expect(VCR.configuration.default_cassette_options[:match_requests_on]).not_to include(:body)
  end

  it "refuses to record unless asked, so a missing cassette cannot reach the network" do
    expect(VCR.configuration.default_cassette_options[:record]).to eq(:none)
  end

  # **Why `spec/recorded/session_flow_spec.rb` pins a clock**, asserted against the cassettes
  # rather than left as a comment someone can delete.
  #
  # A recorded credential is not a fixture — it decays. KSeF issues an access token good for
  # about fifteen minutes, {Ksef::Auth::AccessToken} refreshes at 80% of that, and a replay
  # against the real clock therefore starts requesting a refresh the cassette cannot answer
  # roughly twelve minutes after recording. The first recording passed its verification for
  # exactly that reason and went red overnight with nothing changed.
  #
  # This states the durable half — the lifetime is far shorter than the interval between a
  # recording and the next reader — so removing the clock injection leaves a spec that
  # explains what broke.
  it "records credentials that expire far sooner than the cassettes are replayed" do
    lifetimes = RecordedTier.access_token_lifetimes

    expect(lifetimes).not_to be_empty
    expect(lifetimes).to all(be < 3600)
  end

  # **`auth_refresh_spec`'s "does not renew twice" assertion is enforced by the cassette**, not
  # by the expectation: a second renewal raises `UnhandledHTTPRequestError` only because exactly
  # one refresh interaction was recorded. Nothing said so, and a re-recording that captured two
  # — a slower flow, a retry — would silently downgrade that assertion to `x == x`.
  it "records exactly one token refresh, which is what makes 'it does not renew twice' bite" do
    counts = RecordedTier.request_counts("/auth/token/refresh")

    expect(counts).to include("renews_the_access_token_before_it_expires_without_re-authenticating" => 1)
    expect(counts.values.sum).to eq(1)
  end

  # DESIGN.md §11 Phase 3 publishes 0.1.0. The recorded tier is Phase 2 scope, so it must not
  # still be empty by then — and this is the gate that will say so, rather than a reader
  # noticing. Runs only under KSEF_RELEASE_CHECK=1, like the other release gates.
  it "has at least one cassette before 0.1.0 is published", :release_check do
    expect(RecordedTier).to be_recorded,
                            "no VCR cassette exists. The recorded tier is the last Phase 2 " \
                            "scope item (DESIGN.md §9.1); record it with `rake vcr:record` " \
                            "before publishing."
  end
end
