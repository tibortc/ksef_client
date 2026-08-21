# frozen_string_literal: true

require "simplecov"

# A filtered run — one file, one line, or a tag selector — legitimately exercises only
# part of the library, so the gate would fail on a green suite. It is enforced on full
# runs only; without this, `rspec --tag integration` in nightly CI fails on coverage
# rather than on tests.
FILTERED_RUN = ARGV.any? { |arg| arg.start_with?("spec/", "--tag", "-t", "--example", "-e") }

SimpleCov.start do
  add_filter "/spec/"
  # Codegen output is excluded from the coverage gate (DESIGN.md §9).
  add_filter "lib/ksef/fa3/generated/"
  enable_coverage :line
  minimum_coverage line: 90 unless FILTERED_RUN
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
