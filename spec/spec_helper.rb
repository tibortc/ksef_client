# frozen_string_literal: true

require "simplecov"
require "simplecov-lcov"

# A filtered run — one file, one line, or a tag selector — legitimately exercises only
# part of the library, so the gate would fail on a green suite. It is enforced on full
# runs only; without this, `rspec --tag integration` in nightly CI fails on coverage
# rather than on tests.
#
# **`--pattern` and its value are stripped first, and that is not a nicety.** `rake spec`
# invokes `rspec --pattern spec/**{,/*/**}/*_spec.rb`, whose *value* starts with `spec/` —
# so the naive check read the **full** suite as filtered and skipped the coverage gate
# entirely. `bundle exec rake` therefore never enforced the floors, while CI (which calls
# `bundle exec rspec` directly) always did: the documented definition of done was strictly
# weaker than the thing it claimed to mirror. Found and fixed 2026-08-23.
SELECTORS = ARGV.each_with_index.reject do |argument, index|
  argument == "--pattern" || ARGV[index - 1] == "--pattern"
end.map(&:first)

FILTERED_RUN = SELECTORS.any? { |arg| arg.start_with?("spec/", "--tag", "-t", "--example", "-e") }

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
  # `skip`, not `add_filter`: SimpleCov 1.1 deprecates the older name and prints a line per
  # call on every run — including inside `rake`, where a real coverage failure has to be
  # noticed among them. Same arguments and same behaviour, and the Gemfile pins `~> 1.1`, so
  # the whole permitted range has it.
  skip "/spec/"
  # Codegen output is excluded from the coverage gate (DESIGN.md §9).
  skip "lib/ksef/fa3/generated/"

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
  #
  # Ratcheted 2026-08-24 twice: 95 -> 96 after the parser landed, then 96 -> 97 after validator
  # tier 1. Actual at the second: line 100%, branch 97.92% (519/530), method 100% — so 97 leaves
  # about five branches of slack. 98 was rejected deliberately: actual is 97.92, and a floor that
  # close fails the build on one new uncovered branch anywhere, which is the opposite of what
  # the paragraph above argues for. The eleven uncovered branches are all pre-existing `&.`
  # guards outside the FA(3) model.
  #
  # Re-measured 2026-08-24 after `KOR` and the audit that followed it: line 100%, branch 98.41%
  # (619/629), method 100%. **Still 97**, because 98 would permit twelve uncovered branches
  # against the ten that exist — two branches of slack, so the third new uncovered branch
  # anywhere fails the build. But the caveat above is now visible in the numbers: the
  # denominator went 530 -> 629, so an unchanged floor of 97 permits eighteen uncovered branches
  # where it permitted fifteen. The slack a percentage grants really does drift upward.
  #
  # The ten are pre-existing and unchanged since 4a4d962 (checked by re-running the suite at
  # that commit). Seven are `&.` guards; the other three are plain `if`/`return` guards —
  # `serializer.rb`'s `return if values.nil?` and two in `tasks/ksef_bootstrap.rb` — so the
  # earlier wording "the same ten `&.` guards, outside the FA(3) model" was wrong twice over.
  #
  # **Ratcheted to branch 98 at the Phase 2 boundary (2026-08-26), which is what the paragraph
  # above asks for and what the previous two measurements did not do.** Measured after the
  # field mapping: line 100%, branch 98.66% (741/751), method 100%. The denominator moved
  # 675 -> 689 -> 701 -> 751 in a single day, and an unchanged floor of 97 would have permitted
  # 22 uncovered branches against the ten that exist — the slack a percentage grants really
  # does drift upward. 98 leaves five branches of margin, which is deliberate rather than a
  # knife edge: refactors move the denominator without changing test quality.
  #
  # Previously, after all seven invoice types: line 100%, branch 98.51% (665/675),
  # method 100%. **The ten are still those ten.** They briefly became eleven: the type work
  # added `#vat_rounded_per_line`'s `next unless line.summarised?` guard, whose twin in
  # `#net_by_rate` was tested while it was not — a guard defending a state that genuinely
  # *can* occur, unlike the other ten, and dropping it left the suite green. An audit found it
  # and it now has a test. Worth the note because the count is easy to read as noise: a new
  # uncovered branch in new code is a missing test, and only the ten are the deliberate kind.
  minimum_coverage line: 99, branch: 98, method: 100
end

require "ksef_client"
require "webmock/rspec"

# No spec may reach the network. Live integration specs opt back in explicitly.
WebMock.disable_net_connect!(allow_localhost: false)

# The recorded tier hooks the same WebMock, so it must be configured after that call and
# before any example runs (DESIGN.md §9.1).
require_relative "support/vcr"
require_relative "support/recorded_flow"

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
