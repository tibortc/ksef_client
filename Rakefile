# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "digest"

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

task default: %i[verify:artifacts spec rubocop]
