# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "digest"
require "fileutils"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

def check_pinned_artifacts
  File.read("docs/artifacts.sha256", encoding: "UTF-8").each_line.filter_map do |line|
    next if line.strip.empty?

    expected, path = line.chomp.split("  ", 2)
    next "#{path}: MISSING" unless File.exist?(path)

    actual = Digest::SHA256.file(path).hexdigest
    next "#{path}: expected #{expected}, got #{actual}" unless actual == expected

    puts "#{path}: OK"
    nil
  end
end

namespace :verify do
  desc "Check pinned upstream artifacts against docs/artifacts.sha256"
  task :artifacts do
    failures = check_pinned_artifacts
    next if failures.empty?

    warn "\nPinned artifacts do not match the manifest:"
    failures.each { |f| warn "  #{f}" }
    warn "\nThis means upstream changed, not that the checkout is broken."
    warn "Re-verify against DESIGN.md §2 sources and update docs/REFERENCE.md."
    abort
  end
end

namespace :fa3 do
  desc "Regenerate lib/ksef/fa3/generated/ from the pinned FA(3) XSD"
  task :generate do
    require_relative "tasks/fa3_generator"
    puts "Generating FA(3) metadata..."
    Fa3Codegen::Generator.new.generate!
    puts "Done. `git diff` should be empty unless the schema changed."
  end

  desc "Regenerate docs/field_mapping.md from the declared mapping and the pinned XSD"
  task :field_mapping do
    require "ksef"
    require_relative "tasks/field_mapping"
    Fa3FieldMapping.generate!
  end

  desc "Fail if the committed generated/ or field_mapping.md differs from a fresh run (DESIGN.md §11)"
  task :verify do
    require "ksef"
    require_relative "tasks/fa3_generator"
    require_relative "tasks/field_mapping"

    drifted, generated = Fa3Codegen.drifted_files
    drifted << Fa3FieldMapping::OUT if Fa3FieldMapping.stale?
    abort "Stale or not reproducible: #{drifted.join(", ")}. Regenerate and commit." if drifted.any?

    puts "Codegen is reproducible: #{generated + 1} file(s) byte-identical."
  end
end

namespace :vcr do
  desc "Record the VCR cassettes for the recorded test tier (TEST only, needs credentials). " \
       "Optionally narrow to one file: rake 'vcr:record[spec/recorded/auth_refresh_spec.rb]'"
  task :record, [:target] do |_task, args|
    # **Human-run, and it changes the world.** Recording drives the real TEST service: it opens
    # a session, submits an invoice that cannot be withdrawn, and consumes rate-limited quota
    # (DESIGN.md §6, §9.1). It is not part of `rake`.
    env = (ENV["KSEF_ENV"] || "test").to_sym
    abort "Refusing to record against #{env}. This task is TEST-only (a hard rule)." unless env == :test

    missing = %w[KSEF_TEST_NIP KSEF_TEST_TOKEN].reject { |key| ENV[key].to_s.empty? == false }
    abort "Set #{missing.join(" and ")} first — recording needs a real TEST credential." if missing.any?

    # **Narrowing is the point of the argument, not a convenience.** `record: :all` re-records
    # every cassette it runs, and `session_flow_spec.rb` submits a real invoice per example —
    # so re-recording the whole tier to add one cassette creates permanent TEST invoices for
    # flows that had not changed. Adding `auth_refresh_spec.rb` costs one authentication and
    # no invoice when it is named; two invoices when it is not.
    # **Anchored, not `start_with?`.** The old guard accepted `spec/recorded; curl …` — it only
    # asked how the string began, and the string went on to reach a shell. The pattern now
    # describes the whole argument: the directory, or one path beneath it made of the
    # characters a path is made of.
    target = args[:target].to_s.empty? ? "spec/recorded" : args[:target]
    unless target.match?(%r{\Aspec/recorded(?:/[\w.-]+)*\z})
      abort "Refusing to record #{target.inspect}: expected spec/recorded or a path beneath it."
    end

    puts "Recording #{target} against TEST."
    puts "`spec/recorded/session_flow_spec.rb` creates a permanent TEST invoice per example."
    puts "Cassettes are scrubbed on write; `bundle exec rspec spec/cassette_hygiene_spec.rb`"
    puts "verifies that afterwards, and it is not optional."
    # Argument form, so `target` is one argv entry rather than a fragment of a shell command.
    # With a single string, `sh` runs it through /bin/sh and the interpolation is a shell
    # injection — belt and braces alongside the anchored guard above, because the guard is one
    # regex away from being wrong again.
    sh({ "KSEF_INTEGRATION" => "1", "KSEF_ENV" => "test", "KSEF_VCR_RECORD" => "1" },
       "bundle", "exec", "rspec", target, "--tag", "recorded")
  end
end

# Mirrors what CI runs, so `rake` locally means the same thing as a green matrix leg.
namespace :auth do
  desc "Provision a TEST credential: register a NIP, authenticate by XAdES, mint a KSeF token"
  task :bootstrap do
    require "ksef_client"
    require_relative "tasks/ksef_bootstrap"

    env = (ENV["KSEF_ENV"] || "test").to_sym
    abort "Refusing to run against #{env}. This task is TEST-only (a hard rule)." unless env == :test

    result = KsefBootstrap::Runner.new(configuration: Ksef::Configuration.new(env: env)).call

    puts <<~OUT

      Done. Store these as **environment** secrets on the `ksef-test` environment
      (not repository secrets — those are readable by every workflow in the repo,
      which is more exposure than a live KSeF credential needs). nightly.yml
      declares that environment and reads both (docs/REFERENCE.md §6a.3):

        KSEF_TEST_NIP    #{result.fetch(:nip)}
        KSEF_TEST_TOKEN  #{result.fetch(:token)}

      The token is a confidential credential. Put it straight into GitHub secrets;
      do not write it to a file in this repository. The PESEL used was
      #{result.fetch(:pesel)} — recorded only so the context can be re-provisioned,
      and note that re-creating test data under the same identifier needs a LATER
      createdDate than the previous one (docs/REFERENCE.md §6a.1).
    OUT
  end
end

task default: %i[verify:artifacts fa3:verify spec rubocop]
