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

  # The version a tag names: `v0.1.0` -> `0.1.0`.
  #
  # **This exists because the workflow was calling {.for} with the tag.** `release.yml` passes
  # `github.ref_name`, which for `refs/tags/v0.1.0` is `v0.1.0`, while the CHANGELOG is keyed on
  # `0.1.0`. One character, and `.for` raises on it — so the `announce` job would have failed on
  # every release. It runs `needs: publish`, so the failure lands *after* the gem is on RubyGems:
  # the irreversible half succeeds and the recoverable half breaks.
  #
  # Nothing caught it because the spec and the workflow never met. Eight examples exercised
  # `.for`, all passing a bare version; the workflow — the only caller that exists — passed a
  # tag. The seam between a tested function and its untested call site is where this project
  # keeps finding defects (DESIGN.md §7.2's guards "check that both ends exist, not that they
  # correspond"). `spec/tasks/release_notes_spec.rb` now reads the workflow file.
  #
  # The mapping lives here rather than as a shell substitution so it has one implementation and
  # a test, and so a tag that is not a version at all fails here — where the message names the
  # problem — rather than four lines later as "no such section".
  #
  # **`Gem::Version.correct?` alone is not that check.** Its pattern is fully optional, so it
  # answers `true` for `""` — which is what the tag `v` reduces to. It also accepts `0.1.O`,
  # because a letter segment is a legal *prerelease*, so this does not catch typos and should
  # not be extended to try: `0.1.O` is a version RubyGems would publish. Requiring a leading
  # digit is what rules out the empty string and a branch-shaped tag like `nightly`.
  #
  # @param tag [String] a git tag, with or without the conventional leading "v"
  # @return [String] the version
  # @raise [RuntimeError] if what remains is not a version RubyGems would accept
  def self.version_from_tag(tag)
    version = tag.to_s.delete_prefix("v")
    raise "#{tag.inspect} is not a version tag." unless version.match?(/\A\d/) && Gem::Version.correct?(version)

    version
  end

  # @param version [String] e.g. "0.1.0" — no leading "v"; see {.version_from_tag}
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
