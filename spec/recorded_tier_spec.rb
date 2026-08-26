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
    expect(RecordedTier::SECRET_ENV).to include("KSEF_TEST_TOKEN", "KSEF_TEST_NIP")
  end

  # §9.1, obstacle 1. Encrypted request bodies differ on every run by construction, so a body
  # matcher cannot work — and would present as a flaky test rather than an impossible one.
  it "never matches requests on the body" do
    expect(VCR.configuration.default_cassette_options[:match_requests_on]).not_to include(:body)
  end

  it "refuses to record unless asked, so a missing cassette cannot reach the network" do
    expect(VCR.configuration.default_cassette_options[:record]).to eq(:none)
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
