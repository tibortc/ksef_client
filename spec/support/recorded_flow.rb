# frozen_string_literal: true

# Shared setup for the recorded tier (DESIGN.md §9.1), extracted when a second recorded flow
# arrived so the two files differ only in what they exercise.

# A clock the example moves by hand.
#
# **Replay has to supply its own "now", because a recorded credential decays.** A KSeF access
# token is valid for fifteen minutes and {Ksef::Auth::AccessToken} refreshes at 80% of that, so
# a replay against the real clock reads the recorded credential as stale about twelve minutes
# after recording and issues a `POST /auth/token/refresh` no cassette contains. Seeding from the
# cassette's own `recorded_at` replays the flow as it happened.
#
# It moves rather than merely being fixed so a spec can reach the staleness path deliberately:
# {#advance} past the refresh deadline makes the *next* call to `#bearer` renew, in both modes.
# Recording therefore needs no twelve-minute wait, and replay exercises the real arithmetic
# against the `validUntil` KSeF actually sent rather than a synthetic one.
class RecordedClock
  # @param origin [Time] the moment this flow is pinned to
  def initialize(origin)
    @origin = origin
    @elapsed = 0
  end

  # @return [Time] what the code under test sees as "now"
  def call = @origin + @elapsed

  # @param seconds [Numeric] how far to move
  # @return [self]
  def advance(seconds)
    @elapsed += seconds
    self
  end
end

# ## Recording and replaying are not the same run
#
# The first version of the session flow hardcoded the *replay* placeholders and then tried to
# record with them. KSeF answered `[21405] Invalid NIP format`: `0000000000` passes this gem's
# checksum — only PROD checks the digits (§15.3) — and fails the schema's structural rule that
# the first digit is non-zero (§13). So every value that differs between the two modes is read
# from the environment, and the fallback exists only so a replay can construct.
RSpec.shared_context "with a recorded KSeF flow" do
  def recording? = ENV["KSEF_VCR_RECORD"] == "1"

  # The real context when recording; a format-valid stand-in when replaying. The stand-in is
  # never sent anywhere — requests are matched on method and URI — but `Subject` and
  # `Auth::Token` both validate what they are handed, so it has to be a plausible NIP.
  def context_nip = ENV.fetch("KSEF_TEST_NIP", "9999999999")

  # Scrubbed out of the cassette on write (`spec/support/vcr.rb`).
  def access_token = ENV.fetch("KSEF_TEST_TOKEN", "<KSEF_TEST_TOKEN>")

  let(:credential) { Ksef::Auth::Token.new(context_nip: context_nip, token: access_token) }
  let(:client) { Ksef::Client.new(env: :test, auth: credential, clock: clock) }

  # Captured eagerly, before the first request: replaying consumes interactions out of the
  # list, so `.first` does not stay the first for long.
  let(:clock) { RecordedClock.new(recording? ? Time.now : first_recorded_at) }

  # The moment the cassette was made. Guarded, because an absent cassette otherwise reports
  # `undefined method 'recorded_at' for nil` from inside the clock — which says nothing about
  # the actual problem, and the actual problem is the one this tier is most likely to have.
  def first_recorded_at
    cassette = VCR.current_cassette
    first = cassette && cassette.http_interactions.interactions.first
    return first.recorded_at if first

    raise "No cassette for this example. Record the tier before running it: " \
          "dispatch .github/workflows/record-cassettes.yml, or `rake vcr:record` with " \
          "TEST credentials (DESIGN.md §9.1)."
  end
end
