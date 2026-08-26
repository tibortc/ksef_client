# frozen_string_literal: true

# Gates that only matter at release. Excluded from ordinary runs; `release.yml` sets
# KSEF_RELEASE_CHECK=1 so a tag build fails rather than publishing a broken gem.
RSpec.describe "release readiness", :release_check do
  let(:gemspec) { Gem::Specification.load(File.expand_path("../ksef_client.gemspec", __dir__)) }

  # DESIGN.md §12 item 1 — repo/org placement and author metadata are a human decision,
  # deliberately deferred. This is what stops the placeholders shipping to RubyGems.
  #
  # The sentinel avoids the words TODO/FIXME on purpose: RubyGems refuses to build a gem
  # containing those, which would make the package unbuildable throughout development.
  # The gate lives here instead, so CI can still exercise `gem build` on every push.
  describe "DESIGN.md §12 item 1 metadata placeholders" do
    let(:sentinel) { "UNRESOLVED-DESIGN-12-1" }

    it "has a real author" do
      expect(gemspec.authors.join).not_to include(sentinel)
    end

    it "has a real homepage" do
      expect(gemspec.homepage).not_to include(sentinel)
    end

    it "has metadata URIs that resolve to a real repo" do
      %w[source_code_uri changelog_uri bug_tracker_uri].each do |key|
        expect(gemspec.metadata.fetch(key)).not_to include(sentinel)
      end
    end

    it "has a copyright holder in the licence" do
      licence = File.read(File.expand_path("../LICENSE", __dir__), encoding: "UTF-8")
      expect(licence).not_to include(sentinel)
    end
  end

  describe "gemspec invariants" do
    it "never puts an upper bound on required_ruby_version" do
      # DESIGN.md §3: an upper bound strands users on the next Ruby release.
      expect(gemspec.required_ruby_version.to_s).to eq(">= 3.2.0")
    end

    it "requires MFA for publishing" do
      expect(gemspec.metadata["rubygems_mfa_required"]).to eq("true")
    end

    it "declares exactly the four approved runtime dependencies" do
      # DESIGN.md §4.3 — a fifth is a decision to be flagged, not made in passing.
      expect(gemspec.runtime_dependencies.map(&:name)).to contain_exactly(
        "bigdecimal", "faraday", "nokogiri", "zeitwerk"
      )
    end

    it "ships the bundled FA(3) schemas" do
      expect(gemspec.files).to include("lib/ksef/fa3/schema/schemat_FA(3)_v1-0E.xsd")
    end

    # An XSD under lib/ is there because something reads it at runtime, or will within the
    # current milestone — the UPO schema is pinned ahead of its consumer (docs/REFERENCE.md
    # §1.3). Either way a schema missing from the package is a failure that appears only in
    # the packaged gem, which no local run would catch.
    it "ships every pinned schema, not just the FA(3) ones" do
      on_disk = Dir[File.expand_path("../lib/**/*.xsd", __dir__)]
                .map { |f| f.sub("#{File.expand_path("..", __dir__)}/", "") }
      expect(gemspec.files).to include(*on_disk)
    end

    it "does not ship the design or agent-instruction documents" do
      expect(gemspec.files).not_to include("DESIGN.md", "CLAUDE.md")
    end

    it "does not ship development fixtures" do
      expect(gemspec.files.grep(%r{^spec/})).to be_empty
    end

    # The codegen and the field-mapping generator both live in `tasks/`, outside `lib/`,
    # precisely so they are never packaged — CLAUDE.md states it as a rule. Until 2026-08-26
    # nothing enforced it: the rule held only because `spec.files`' globs happen not to reach
    # there, which is incidental rather than intended.
    it "does not ship the generators" do
      expect(gemspec.files.grep(%r{^tasks/})).to be_empty
    end

    # It is the answer to "is my field supported", so it belongs in the installed gem rather
    # than only in the repository.
    it "ships the field mapping, which is for the gem's users" do
      expect(gemspec.files).to include("docs/field_mapping.md")
    end
  end
end
