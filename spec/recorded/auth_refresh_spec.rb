# frozen_string_literal: true

require "spec_helper"

# `POST /auth/token/refresh`, replayed against the response KSeF actually sent (DESIGN.md §9.1).
#
# ## Why this needed its own recording
#
# **Nothing had ever seen this endpoint's response body.** `Auth::Client#refresh` reads
# `body["accessToken"]` and hands it to `TokenInfo.from`, and that envelope was inferred from the
# OpenAPI contract rather than observed — `docs/REFERENCE.md` §4.2 records that the 2026-08-23
# live run covered five of the six auth calls and not this one. A wrong guess does not raise: it
# produces `TokenInfo.from(nil)`, i.e. a credential holding no token, which surfaces much later
# as {Ksef::Auth::AccessToken}'s `@access.nil?` guard.
#
# It also fills a hole the session cassettes opened. Those pin their clock to the moment of
# recording precisely so the credential never goes stale, so **the recorded tier had no path
# through `renew!` at all**. This one takes that path deliberately.
#
# ## One example, and it costs no invoice
#
# Unlike `session_flow_spec.rb`, nothing here is unwithdrawable: this authenticates and renews.
# The expensive part of a recording is the permanent TEST invoice, and this makes none.
RSpec.describe "the token refresh flow, recorded", :recorded, :vcr do
  include_context "with a recorded KSeF flow"

  # Past the refresh deadline whatever lifetime KSeF granted, and deliberately **short of
  # expiry**: the threshold is 80% of the observed lifetime, so 90% of it is always stale and
  # never expired. That is the property under test — {Ksef::Auth::AccessToken} renews *before*
  # the credential dies, so a request never carries a token that expires mid-flight, which on a
  # non-idempotent invoice submission is the failure this gem works hardest to avoid.
  #
  # Derived rather than hardcoded: the two session cassettes observed a fifteen-minute token,
  # but a number taken from one recording is an assumption, and this one would fail silently by
  # simply not refreshing.
  def advance_past_refresh_deadline
    clock.advance(((client.credential.valid_until - clock.call) * 0.9).ceil)
  end

  it "renews the access token before it expires, without re-authenticating" do
    original = client.credential.valid_until
    expect(original).to be_a(Time)

    advance_past_refresh_deadline
    expect(client.credential).not_to be_expired(clock.call)

    # The renewal happens here, inside `#bearer` — no explicit `refresh!`, so what is exercised
    # is the staleness decision itself, against a `validUntil` KSeF really sent.
    client.credential.bearer

    # A later expiry is what proves the response parsed. Had `body["accessToken"]` been the
    # wrong envelope, `TokenInfo.from(nil)` would leave `valid_until` nil rather than moving it.
    expect(client.credential.valid_until).to be > original

    # And the pair survived: refreshing replaces the access token only, so the refresh token is
    # still what a later renewal would use. §4.2 puts its life at up to seven days.
    expect(client.credential).not_to be_refresh_token_expired

    # The renewed token is fresh, so a second call must **not** renew again. The cassette is
    # what enforces that: only one refresh was recorded, so a second would raise
    # `VCR::Errors::UnhandledHTTPRequestError` rather than quietly passing.
    renewed = client.credential.valid_until
    client.credential.bearer
    expect(client.credential.valid_until).to eq(renewed)
  end
end
