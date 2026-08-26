# frozen_string_literal: true

# The release notes for a version, taken from `CHANGELOG.md` (DESIGN.md §10).
#
# Development-only: this file lives outside `lib/` so it is never packaged.
#
# **The notes are the ledger, not a generated commit list.** This project writes its CHANGELOG
# by hand, with the reasoning and the sources, because a release note that says "fix parser bug"
# is worth less than one saying which document the parser was reading wrongly. Generating notes
# from commit subjects would throw that away and quietly make the CHANGELOG decorative.
#
# So the GitHub release publishes exactly what the CHANGELOG says, and fails when the CHANGELOG
# has nothing to say — which is the useful failure: it means the section was never written.
module ReleaseNotes
  CHANGELOG = "CHANGELOG.md"

  # Headings look like `## [0.1.0.rc1] — 2026-08-22`, and `## [Unreleased]` above them.
  HEADING = /^## \[([^\]]+)\]/

  # @param version [String] e.g. "0.1.0" — no leading "v"
  # @param path [String] the changelog to read
  # @return [String] the section body, without its heading, stripped of trailing blank lines
  # @raise [RuntimeError] if the section is absent, empty, or is the unreleased one
  def self.for(version, path: CHANGELOG)
    raise "Refusing to release the #{version.inspect} section." if version.casecmp("unreleased").zero?

    body = section(File.read(path, encoding: "UTF-8"), version)
    raise missing(version, path) if body.nil?
    raise "#{path} has a [#{version}] heading with nothing under it." if body.empty?

    body
  end

  # @return [String, nil] nil when no heading names this version
  def self.section(changelog, version)
    lines = changelog.lines
    start = lines.index { |line| line[HEADING, 1] == version }
    return nil if start.nil?

    rest = lines[(start + 1)..]
    stop = rest.index { |line| line.match?(HEADING) } || rest.length
    rest[0...stop].join.strip
  end

  def self.missing(version, path)
    found = File.read(path, encoding: "UTF-8").scan(HEADING).flatten
    "#{path} has no [#{version}] section. It lists: #{found.join(", ")}. " \
      "Move the [Unreleased] entries under a [#{version}] heading before tagging."
  end
end
