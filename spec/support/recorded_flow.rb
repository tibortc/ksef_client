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
# A sleeper that does nothing and remembers being asked.
#
# Doing nothing is what a replay needs — every answer is already on disk. Remembering is what
# makes the seam *checkable*: removing the injection leaves the suite green and 54× slower, and
# a no-op lambda cannot tell you it was bypassed.
class RecordingSleeper
  attr_reader :calls

  def initialize = @calls = []

  def call(seconds) = @calls << seconds
end

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
  let(:client) { Ksef::Client.new(env: :test, auth: credential, clock: clock, sleeper: sleeper) }

  # Real waits while recording — the authentication really is asynchronous — and none while
  # replaying, where every answer is already on disk. Without this the tier spent eight of its
  # nine seconds asleep between recorded status calls.
  #
  # The replay sleeper *records* rather than merely doing nothing, so {#slept} can prove it was
  # used. Removing the injection is otherwise completely silent: the suite still passes, 54×
  # slower, and nothing says so.
  let(:sleeper) { recording? ? method(:sleep) : RecordingSleeper.new }

  # `Auth::Client#wait_until_complete` sleeps *between* polls, so a flow whose first status
  # answer was already terminal sleeps not at all — and one of these cassettes is exactly that.
  # The expected count therefore comes from the cassette rather than from an assumption that
  # every flow waits, which is what a first version of this guard assumed and got wrong.
  after do |example|
    next if recording? || example.exception

    # **At least**, not exactly: the authentication poll is the sleep this can count from the
    # cassette, and a spec may poll something else as well — `invoice_download_spec` waits for
    # the session to finish processing, through the same injected sleeper. The floor is what
    # catches the regression this guards, since removing the injection takes the count to zero.
    expected = [cassette_facts[:status_polls] - 1, 0].max
    next if sleeper.calls.size >= expected

    # `raise` rather than `expect`: an assertion belongs in an example, and this is a hook.
    raise "expected at least #{expected} injected sleep(s) between " \
          "#{cassette_facts[:status_polls]} recorded status polls, got #{sleeper.calls.size}. " \
          "If it is 0, this replay used the real `sleep` — check `sleeper:` still reaches " \
          "`Auth::Client#wait_until_complete` (DESIGN.md §9.1)."
  end

  # Read once, **before the first request**: replaying consumes interactions out of the list, so
  # neither `.first` nor a count survives the flow. `clock` forces this and `client` forces
  # `clock`, so both facts are captured while the cassette is still whole.
  let(:cassette_facts) do
    next { origin: Time.now, status_polls: 0 } if recording?

    interactions = recorded_interactions
    {
      origin: interactions.first.recorded_at,
      # `GET /v2/auth/{referenceNumber}`. A reference number carries the `-AU-` document code
      # (docs/REFERENCE.md §13), which separates these from every other auth route.
      status_polls: interactions.count { |i| i.request.uri.include?("-AU-") }
    }
  end

  let(:clock) { RecordedClock.new(cassette_facts[:origin]) }

  # Guarded, because an absent cassette otherwise reports `undefined method 'recorded_at' for
  # nil` from inside the clock — which says nothing about the actual problem, and the actual
  # problem is the one this tier is most likely to have.
  def recorded_interactions
    cassette = VCR.current_cassette
    interactions = cassette ? cassette.http_interactions.interactions : []
    return interactions unless interactions.empty?

    raise "No cassette for this example. Record the tier before running it: " \
          "dispatch .github/workflows/record-cassettes.yml, or `rake vcr:record` with " \
          "TEST credentials (DESIGN.md §9.1)."
  end
end
