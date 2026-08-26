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
    Fa3FieldMapping.generate! && puts("Wrote #{Fa3FieldMapping::OUT}.")
  end

  desc "Fail if the committed generated/ or field_mapping.md differs from a fresh run (DESIGN.md §11)"
  task :verify do
    require "ksef"
    require_relative "tasks/fa3_generator"
    require_relative "tasks/field_mapping"

    before = Dir["#{Fa3Codegen::OUT_DIR}/*.rb"].to_h { |f| [f, File.read(f, encoding: "UTF-8")] }
    Fa3Codegen::Generator.new.generate!
    drifted = before.reject { |path, body| File.read(path, encoding: "UTF-8") == body }.keys
    abort "Stale or non-reproducible: #{drifted.join(", ")}. Commit the regenerated files." if drifted.any?
    abort "#{Fa3FieldMapping::OUT} is stale. Run `rake fa3:field_mapping`." if Fa3FieldMapping.stale?

    puts "Codegen is reproducible: #{before.size + 1} file(s) byte-identical."
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
