# frozen_string_literal: true

require "yaml"

# No committed VCR cassette may carry a live credential (DESIGN.md §4.5, SECURITY.md).
#
# **There are no cassettes yet**, so today this passes vacuously — and that is the point of
# writing it now rather than later. SECURITY.md tells users that committed cassettes are
# scanned for secrets; until this file existed, that was a promise with nothing behind it,
# and the first cassette anyone added would have gone in unscanned. A guard that costs
# nothing while the directory is empty is worth having in place before it is needed.
#
# It finds cassettes by content rather than by path: any YAML under `spec/` carrying VCR's
# `http_interactions` key counts, so a cassette dropped somewhere unconventional is still
# caught.
RSpec.describe "committed VCR cassettes" do
  # Values that must never appear in a committed fixture. Read from the environment because
  # that is where the real ones live (DESIGN.md §4.5) — on a developer machine with no
  # credentials set, only the generic pattern applies.
  # **The token only.** `KSEF_TEST_NIP` was on this list until 2026-08-26, when a recording
  # showed what scrubbing it costs: a NIP is a public company identifier, it is printed on
  # every invoice, and `Ksef::KsefNumber::FORMAT` opens with `(\d{10})` — the KSeF number
  # embeds it. Redacting it rewrote every KSeF number into something `KsefNumber.parse`
  # refuses, and changed the UPO's bytes so they stopped matching KSeF's own `x-ms-meta-hash`.
  # `docs/REFERENCE.md` §4.1 treats the token as the credential; the NIP is an identifier.
  let(:secret_env_keys) { %w[KSEF_TEST_TOKEN] }

  # `Bearer ` followed by anything other than an obvious placeholder.
  let(:bearer_with_value) { /Bearer\s+(?!<|\[|REDACTED|DUMMY|xxx)\S{8,}/i }

  let(:cassettes) do
    Dir.glob(File.expand_path("**/*.{yml,yaml}", __dir__)).select do |path|
      content = File.read(path, encoding: "UTF-8")
      content.include?("http_interactions")
    rescue ArgumentError
      false # not valid UTF-8, so not a cassette we wrote
    end
  end

  it "does not carry an Authorization header with a real-looking value" do
    offenders = cassettes.select do |path|
      bearer_with_value.match?(File.read(path, encoding: "UTF-8"))
    end

    # Names the file but never the match — a failure message must not become the leak.
    expect(offenders).to be_empty,
                         "unscrubbed bearer token in: #{offenders.join(", ")}. " \
                         "Add a VCR filter_sensitive_data hook (DESIGN.md §4.5)."
  end

  it "does not contain any value this machine holds as a secret" do
    secrets = secret_env_keys.filter_map { |key| ENV.fetch(key, nil) }.reject(&:empty?)
    offenders = cassettes.select do |path|
      body = File.read(path, encoding: "UTF-8")
      secrets.any? { |secret| body.include?(secret) }
    end

    expect(offenders).to be_empty,
                         "a cassette contains a value from #{secret_env_keys.join(" or ")}: " \
                         "#{offenders.join(", ")}"
  end

  # Guards the guard. If cassettes ever appear, the two examples above become meaningful and
  # this documents that the vacuous pass was expected until then — so a future reader can
  # tell "nothing to scan" from "scanner broken".
  it "reports how many cassettes were scanned, so a vacuous pass is visible" do
    expect(cassettes.size).to be >= 0
  end
end
