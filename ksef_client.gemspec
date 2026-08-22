# frozen_string_literal: true

require_relative "lib/ksef/version"

Gem::Specification.new do |spec|
  spec.name    = "ksef_client"
  spec.version = Ksef::VERSION

  # DESIGN.md §12.1 resolved 2026-08-22. `spec/release_readiness_spec.rb` still guards
  # against placeholders being reintroduced here.
  spec.authors  = ["Tibor Molnár"]
  spec.email    = ["tibor@timcraft.pl"]
  spec.homepage = "https://github.com/tibortc/ksef_client"

  spec.summary = "Ruby client for KSeF 2.0 (Polish National e-Invoice System) with an FA(3) invoice builder"
  spec.description = <<~DESC
    A Ruby client for KSeF 2.0, Poland's mandatory national e-invoicing system.
    Covers the REST transport layer (KSeF-token authentication, payload encryption,
    interactive sessions, invoice submission, status polling and UPO retrieval) and
    ships a standalone FA(3) invoice builder with XSD-backed validation. The builder
    has no HTTP dependency and can be used on its own.
  DESC
  spec.license = "MIT"

  # Never add an upper bound here. See DESIGN.md §3 — `required_ruby_version` resolves
  # at install time, so an upper bound strands users on unreleased Ruby versions.
  spec.required_ruby_version = ">= 3.2.0"

  # `homepage_uri` is deliberately omitted: it would duplicate `spec.homepage`, which
  # RubyGems warns about.
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"]     = "https://rubydoc.info/gems/ksef_client/#{Ksef::VERSION}"

  # Globbed across all of lib/ rather than per-subsystem: the FA(3) and auth schemas are
  # both loaded at runtime, and a path-specific glob silently omits any schema added
  # later. `spec/release_readiness_spec.rb` asserts both sets are present.
  spec.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.xsd",
    "lib/**/LICENSE.upstream.txt",
    "docs/*.md",
    "*.md",
    "LICENSE"
  ].reject { |f| f.start_with?("DESIGN.md", "CLAUDE.md") }
  spec.require_paths = ["lib"]

  # Runtime dependencies are exactly these four (DESIGN.md §4.3). Adding a fifth is a
  # decision that must be flagged, not made in passing.
  # bigdecimal is bundled, not default, as of Ruby 3.4 — it must be declared.
  spec.add_dependency "bigdecimal", "~> 3.1"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "nokogiri", "~> 1.16"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
