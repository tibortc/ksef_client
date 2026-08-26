# frozen_string_literal: true

require "yaml"
require "tmpdir"

# No committed VCR cassette may carry a live credential (DESIGN.md §4.5, SECURITY.md).
#
# It finds cassettes by content rather than by path: any YAML under `spec/` carrying VCR's
# `http_interactions` key counts, so a cassette dropped somewhere unconventional is still
# caught.
#
# ## Scan the decoded bodies, not only the file
#
# Every check here reads text, and **a cassette is not entirely text**. YAML writes a body it
# cannot represent as a plain scalar as `!binary`, i.e. base64 — five of the tier's bodies are
# stored that way today. A secret inside one is invisible to a regex over the file and to
# `include?` of a known value alike, because what is on disk is base64 of the body rather than
# the body.
#
# That is not hypothetical for the field that has actually leaked: the redeem response carries
# both tokens in a JSON body, and whether YAML stores that body as a scalar or as `!binary`
# depends on bytes nobody controls. So {#scannable} appends the *decoded* bodies and header
# values to the raw text, and the checks run over the whole of it.
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

  # A JWT is unmistakable — `eyJ` is base64 for `{"`, and the dot separates its segments.
  # Named so the planted-secret example below can assert against the same pattern the real
  # check uses, rather than against a copy of it that could drift.
  let(:jwt_pattern) { /eyJ[A-Za-z0-9_-]{8,}\./ }

  # **A pre-signed URL is a credential that is not shaped like one**, which is how two cassettes
  # reached git carrying a live three-day Azure SAS while this file passed 5/5. The path is
  # public; the query string *is* the authorisation. `sig` is the HMAC; `skoid`/`sks` identify
  # the delegation key. Any of them with a real value means an unscrubbed capability.
  #
  # `(?!<)` lets the scrubbed form through — `?<REDACTED-SIGNATURE>` — so this distinguishes
  # "redacted" from "never signed".
  let(:signed_url_pattern) { /[?&](?:sig|skoid|sks)=(?!<)[^&"'\s]{8,}/ }

  let(:cassettes) do
    Dir.glob(File.expand_path("**/*.{yml,yaml}", __dir__)).select do |path|
      content = File.read(path, encoding: "UTF-8")
      content.include?("http_interactions")
    rescue ArgumentError
      false # not valid UTF-8, so not a cassette we wrote
    end
  end

  # The raw file plus everything YAML may have encoded out of plain sight: each interaction's
  # decoded request and response body, and every header value.
  def scannable(path)
    raw = File.read(path, encoding: "UTF-8")
    interactions = YAML.safe_load(raw)["http_interactions"] || []
    parts = interactions.flat_map do |interaction|
      %w[request response].flat_map do |side|
        [interaction.dig(side, "body", "string")] + (interaction.dig(side, "headers") || {}).values.flatten
      end
    end
    ([raw] + parts).compact.join("\n")
  end

  it "does not carry an Authorization header with a real-looking value" do
    offenders = cassettes.select do |path|
      bearer_with_value.match?(scannable(path))
    end

    # Names the file but never the match — a failure message must not become the leak.
    expect(offenders).to be_empty,
                         "unscrubbed bearer token in: #{offenders.join(", ")}. " \
                         "Add a VCR filter_sensitive_data hook (DESIGN.md §4.5)."
  end

  # **The check that was missing, and it is the one that mattered.** The two examples above
  # scan for a `Bearer ` header and for values this machine holds in its environment. KSeF's
  # redeem response carries an access token *and* a refresh token in the JSON body — neither is
  # a header, and neither is an env value on a machine that recorded rather than stored them.
  # So the first successful recording carried a live refresh token, valid for about a week,
  # past both checks. Caught by reading the file; nothing reached git.
  #
  # A JWT is unmistakable — `eyJ` is base64 for `{"` — so the shape is worth scanning for
  # wherever it appears, not only where a token is expected to appear.
  it "does not contain anything shaped like a JSON Web Token" do
    offenders = cassettes.select { |path| jwt_pattern.match?(scannable(path)) }

    expect(offenders).to be_empty,
                         "an unscrubbed JWT is in: #{offenders.join(", ")}. " \
                         "Check RecordedTier.redact covers the field it came from."
  end

  # DESIGN.md §9.1 hard requirement 1 lists the pre-signed `downloadUrl` signature alongside
  # tokens and key material. The URI matcher stripped those parameters from the start; nothing
  # scrubbed them, and nothing looked for them, until 2026-08-26.
  it "does not contain a pre-signed URL that still carries its signature" do
    offenders = cassettes.select { |path| signed_url_pattern.match?(scannable(path)) }

    expect(offenders).to be_empty,
                         "an unscrubbed pre-signed URL is in: #{offenders.join(", ")}. " \
                         "RecordedTier::SIGNED_URL_FIELD should have stripped its query."
  end

  it "does not contain any value this machine holds as a secret" do
    secrets = secret_env_keys.filter_map { |key| ENV.fetch(key, nil) }.reject(&:empty?)
    offenders = cassettes.select do |path|
      # `.scrub`, because `String#include?` answers **false** on a broken-encoding receiver
      # rather than raising — so a single invalid byte anywhere would make the check against
      # the real live token silently pass. Failing open is the one thing this must not do.
      body = scannable(path).scrub
      secrets.any? { |secret| body.include?(secret) }
    end

    expect(offenders).to be_empty,
                         "a cassette contains a value from #{secret_env_keys.join(" or ")}: " \
                         "#{offenders.join(", ")}"
  end

  # **Guards the scanner against the thing it was blind to**, with a planted secret rather than
  # an assertion about the scanner's own definition.
  #
  # One non-ASCII byte anywhere in a body makes Psych store the whole body as `!binary`, and a
  # Polish name is not an edge case in KSeF data — `Łódź` in a seller's name is enough. A JWT
  # inside such a body is invisible to a regex over the file and to `include?` of a known value
  # alike. That is precisely the response that leaked once: the redeem body carries both tokens,
  # and whether it holds a diacritic is not something this project controls.
  it "finds a JWT that YAML stored as !binary, which a scan of the file cannot see" do
    jwt = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gF"
    body = %({"accessToken":{"token":"#{jwt}"},"seller":"Łódź"}).b

    Dir.mktmpdir do |dir|
      path = File.join(dir, "planted.yml")
      File.write(path, YAML.dump({ "http_interactions" =>
        [{ "response" => { "body" => { "string" => body }, "headers" => {} } }] }))

      raw = File.read(path, encoding: "UTF-8")
      expect(raw).to include("!binary")
      expect(raw).not_to match(jwt_pattern)

      expect(scannable(path)).to match(jwt_pattern)
    end
  end

  # Guards the guard — and it used to be `be >= 0`, which is the vacuous pass it exists to
  # expose, in the file written to expose vacuous passes. `size` is never negative.
  #
  # Now it asserts the scanner actually found the cassettes that are committed, so a broken
  # glob or a moved directory turns this red instead of quietly scanning nothing.
  it "scans every committed cassette, so a vacuous pass is visible" do
    committed = Dir.glob(File.expand_path("cassettes/**/*.yml", __dir__))

    expect(committed).not_to be_empty
    expect(cassettes).to include(*committed)
  end
end
