# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
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
end
