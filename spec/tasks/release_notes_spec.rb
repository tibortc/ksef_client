# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"
require_relative "../../tasks/release_notes"

# The GitHub release's body (DESIGN.md §10).
#
# What is worth testing is not the formatting — the notes are whatever the CHANGELOG says — but
# the **refusals**. A release workflow that quietly published empty notes, or the unreleased
# section, would be worse than one that failed: the CHANGELOG is where this project records why
# a change was made, and a release that silently omits it looks finished.
RSpec.describe ReleaseNotes do
  def changelog(body)
    dir = Dir.mktmpdir
    path = File.join(dir, "CHANGELOG.md")
    File.write(path, body)
    path
  end

  let(:sample) do
    <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      - something not yet released

      ## [0.2.0] — 2026-09-01

      ### Added

      - the thing

      ## [0.1.0] — 2026-08-01

      - the first thing
    MARKDOWN
  end

  it "returns the section for a version, without its heading" do
    notes = described_class.for("0.2.0", path: changelog(sample))

    expect(notes).to eq("### Added\n\n- the thing")
  end

  it "stops at the next version rather than running to the end of the file" do
    expect(described_class.for("0.2.0", path: changelog(sample))).not_to include("the first thing")
  end

  it "reads the last section, which has no heading after it" do
    expect(described_class.for("0.1.0", path: changelog(sample))).to eq("- the first thing")
  end

  # The mistake this is here to catch: tagging before moving the entries out of [Unreleased].
  it "refuses a version the changelog does not mention, and says what it does" do
    expect { described_class.for("9.9.9", path: changelog(sample)) }
      .to raise_error(/no \[9\.9\.9\] section.*It lists: Unreleased, 0\.2\.0, 0\.1\.0/m)
  end

  it "refuses to publish the unreleased section under a version number" do
    expect { described_class.for("Unreleased", path: changelog(sample)) }
      .to raise_error(/Refusing to release/)
    expect { described_class.for("unreleased", path: changelog(sample)) }
      .to raise_error(/Refusing to release/)
  end

  it "refuses a heading with nothing under it" do
    empty = changelog("## [0.3.0] — 2026-10-01\n\n## [0.2.0] — 2026-09-01\n\n- x\n")

    expect { described_class.for("0.3.0", path: empty) }
      .to raise_error(/heading with nothing under it/)
  end

  # Guards the real file, so the release workflow's dependency on it is not discovered at tag
  # time. `[Unreleased]` must exist for the next release to be written into.
  it "finds an unreleased section in the committed changelog" do
    expect(described_class.section(File.read("CHANGELOG.md", encoding: "UTF-8"), "Unreleased"))
      .not_to be_nil
  end

  describe ".version_from_tag" do
    it "drops the conventional leading v" do
      expect(described_class.version_from_tag("v0.1.0")).to eq("0.1.0")
      expect(described_class.version_from_tag("v0.1.0.rc2")).to eq("0.1.0.rc2")
    end

    it "accepts a tag that never had one" do
      expect(described_class.version_from_tag("0.1.0")).to eq("0.1.0")
    end

    it "refuses a tag that is not a version at all" do
      # `v` alone is the one that matters: it reduces to `""`, for which
      # `Gem::Version.correct?` answers **true** — its pattern is entirely optional.
      expect { described_class.version_from_tag("v") }.to raise_error(/not a version tag/)
      expect { described_class.version_from_tag("nightly") }.to raise_error(/not a version tag/)
    end

    # Documented because it looks like a bug and is not: a letter segment is a legal
    # prerelease, so `0.1.O` is a version RubyGems would publish. This is not a typo checker
    # and must not be turned into one.
    it "passes a version that merely looks like a typo, because RubyGems would accept it" do
      expect(described_class.version_from_tag("v0.1.O")).to eq("0.1.O")
    end
  end

  # **What was missing was a test of the *call*, not the function.**
  #
  # `release.yml` is this module's only caller, and it passed `github.ref_name` — the *tag* —
  # where every example above passes a version. `ReleaseNotes.for("v0.1.0")` raises, so the
  # `announce` job would have failed on every release; and it runs `needs: publish`, so that
  # failure lands *after* the gem is on RubyGems. The irreversible half succeeds and the
  # recoverable half breaks.
  #
  # Eight passing examples and a broken caller: the seam between a tested function and its
  # untested call site is where this project keeps finding defects. So this reads the workflow.
  describe "the release workflow's use of it" do
    let(:notes_step) do
      YAML.safe_load_file(".github/workflows/release.yml")
          .dig("jobs", "announce", "steps")
          .find { |step| step["run"].to_s.include?("ReleaseNotes") }
    end

    # Newest first, ignoring the unreleased section — so this keeps meaning the same thing as
    # versions are added.
    def released_versions
      File.read("CHANGELOG.md", encoding: "UTF-8").scan(described_class::HEADING).flatten - ["Unreleased"]
    end

    it "takes the tag from the environment, never interpolated into the script" do
      expect(notes_step.fetch("env")).to eq("TAG" => "${{ github.ref_name }}")
      expect(notes_step.fetch("run")).not_to include("${{")
    end

    it "routes the tag through the tag-to-version mapping rather than straight in" do
      expect(notes_step.fetch("run")).to include("version_from_tag")
    end

    # The end-to-end claim, against the committed changelog and a tag in the form git holds:
    # what the job does, minus the runner.
    it "resolves real notes from a real tag" do
      version = released_versions.first

      expect(described_class.for(described_class.version_from_tag("v#{version}"))).not_to be_empty
    end
  end
end
