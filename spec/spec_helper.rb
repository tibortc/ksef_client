# frozen_string_literal: true

require "simplecov"
require "simplecov-lcov"

# A filtered run — one file, one line, or a tag selector — legitimately exercises only
# part of the library, so the gate would fail on a green suite. It is enforced on full
# runs only; without this, `rspec --tag integration` in nightly CI fails on coverage
# rather than on tests.
FILTERED_RUN = ARGV.any? { |arg| arg.start_with?("spec/", "--tag", "-t", "--example", "-e") }

SimpleCov::Formatter::LcovFormatter.config do |c|
  # A single lcov.info rather than one file per source file, which is what the Coveralls
  # uploader expects.
  c.report_with_single_file = true
  c.single_report_path = "coverage/lcov.info"
end

# HTML stays for local use; LCOV is what CI uploads.
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::LcovFormatter]
)

SimpleCov.start do
  add_filter "/spec/"
  # Codegen output is excluded from the coverage gate (DESIGN.md §9).
  add_filter "lib/ksef/fa3/generated/"

  enable_coverage :line
  # Line coverage alone was 99% while branch coverage was 83% — conditional paths were
  # going untested behind fully-covered lines. Method coverage is a cheap regression
  # guard on top: it catches a method nothing calls at all.
  enable_coverage :branch
  enable_coverage :method

  next if FILTERED_RUN

  # Floors sit just under what the suite actually achieves, so they ratchet rather than
  # aspire. Raise them when the real numbers move up; do not lower them to make a change
  # pass. Actual at last ratchet (2026-08-22): line 100%, branch 97.14%, method 100%.
  #
  # Measured after the crypto module and the KSeF-token flow (2026-08-23): line 100%,
  # branch 96.79% (272/281), method 100%. **Deliberately not re-ratcheted here.** Branch 96
  # would leave two branches of slack, which is the knife edge the paragraph above argues
  # against; the ratchet is scheduled for the Phase 2 boundary, where the codebase stops
  # moving under it. The nine uncovered branches are all `&.` guards against states that
  # cannot occur — none of them in the new crypto code, which is fully covered on both
  # criteria.
  #
  # There is deliberate margin rather than a knife edge at the actuals: a floor pinned to
  # the exact current figure fails on refactors that change nothing about test quality —
  # extract a method with an early return and the build goes red for no reason. A ratchet
  # you end up lowering is worse than one set a little loose.
  #
  # Branch is not 100% because the remaining gaps are `&.` guards against states that
  # cannot occur: a completed Faraday response always carries headers, and the pinned XSD
  # always has exactly one import with an http location. Contorting tests to reach them
  # would prove nothing.
  #
  # Caveat for future phases: these are percentages, so the absolute number of untested
  # branches they permit grows with the codebase. Phase 2 roughly doubles it, at which
  # point branch 95 quietly allows twice today's slack. Re-ratchet at each phase boundary,
  # not once (CLAUDE.md records this in the Phase 2 definition of done).
  minimum_coverage line: 99, branch: 95, method: 100
end

require "ksef_client"
require "webmock/rspec"

# No spec may reach the network. Live integration specs opt back in explicitly.
WebMock.disable_net_connect!(allow_localhost: false)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus

  # Release gates are noise during development and blocking at release. `release.yml`
  # sets KSEF_RELEASE_CHECK=1.
  config.filter_run_excluding(:release_check) unless ENV["KSEF_RELEASE_CHECK"] == "1"

  # Live integration specs reach the network and consume shared TEST-environment state, so
  # they are opt-in by an explicit variable rather than by tag alone. RSpec ANDs exclusion
  # filters with CLI inclusions, so `--tag integration` on its own would match nothing if
  # this exclusion were unconditional — the env var is what actually lifts it.
  config.filter_run_excluding(:integration) unless ENV["KSEF_INTEGRATION"] == "1"

  # WebMock is disabled suite-wide above. Integration specs opt back in for their own
  # duration only, so a failure cannot leave the network open for whatever runs next.
  config.around(:each, :integration) do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: false)
  end
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  # DESIGN.md §4.5: integration specs must refuse to run against production.
  config.before(:suite) do
    abort "Refusing to run the suite with KSEF_ENV=prod (DESIGN.md §4.5)" if ENV["KSEF_ENV"] == "prod"
  end
end
