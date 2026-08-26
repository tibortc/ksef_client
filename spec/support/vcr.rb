# frozen_string_literal: true

require "vcr"
require "yaml"
require "json"
require "time"

# The recorded test tier (DESIGN.md §9.1).
#
# It answers a question neither of the other tiers does: **does the flow still work against
# responses KSeF actually sent, on a machine with no credentials, in under a second?** WebMock
# proves our request shapes match our own assumptions; the nightly proves KSeF still accepts
# what we build. This proves the multi-step flows still parse bytes the service really produced
# — per push, for a contributor who has no TEST NIP.
#
# ## Scrubbing comes first, and is why this file exists before any cassette
#
# §4.5 requires tokens, JWTs and keys to be scrubbed via filter hooks, and
# `spec/cassette_hygiene_spec.rb` scans committed cassettes for exactly that. Both were written
# before the first recording deliberately: a cassette recorded without these hooks and then
# committed is a credential leak that `git` remembers.
module RecordedTier
  DIR = File.expand_path("../cassettes", __dir__)

  # Env vars whose values must never reach a cassette. Read rather than listed literally, so a
  # machine that holds a real credential scrubs its own.
  #
  # **`KSEF_TEST_NIP` is deliberately not here, and that took a failed recording to learn.**
  # A NIP is a public company identifier: it is printed on every invoice, and
  # `Ksef::KsefNumber::FORMAT` opens with `(\d{10})` — the KSeF number *embeds* it. Scrubbing
  # it therefore rewrote the middle of every KSeF number into `<KSEF_TEST_NIP>-20260826-…`,
  # which `KsefNumber.parse` refuses, and altered the UPO's bytes so they no longer matched the
  # `x-ms-meta-hash` KSeF sent, which `UPO::Document#verify!` refuses.
  #
  # Both of those checks are things **only** a real response can give — our CRC-8 meeting a
  # number KSeF generated, and KSeF's own integrity header over its own bytes — so scrubbing
  # the NIP cost exactly the assertions the recorded tier exists for. `docs/REFERENCE.md` §4.1
  # classes the **token** as the confidential thing and says nothing about the NIP; confirmed
  # as a deliberate decision by the maintainer, 2026-08-26.
  SECRET_ENV = %w[KSEF_TEST_TOKEN].freeze

  # @return [Boolean] whether anything has been recorded yet
  def self.recorded? = Dir.glob(File.join(DIR, "**", "*.yml")).any?

  # How long each recorded access token was valid for, in seconds — `validUntil` measured from
  # the `recorded_at` of the interaction that carried it.
  #
  # Exists so `spec/recorded_tier_spec.rb` can assert the fact that forces a pinned clock on
  # replay, rather than that fact living only in a comment. See {Ksef::Client#initialize}.
  #
  # @return [Array<Float>]
  def self.access_token_lifetimes
    # `Dir.glob` sorts as of Ruby 3.0 and the floor is 3.2, so no `.sort` is needed.
    Dir.glob(File.join(DIR, "**", "*.yml")).flat_map do |file|
      interactions = YAML.safe_load_file(file)["http_interactions"] || []
      interactions.filter_map { |interaction| access_token_lifetime(interaction) }
    end
  end

  # How many interactions in each cassette are a request to `path`.
  #
  # @return [Hash{String => Integer}] cassette basename => count
  def self.request_counts(path_fragment)
    Dir.glob(File.join(DIR, "**", "*.yml")).to_h do |file|
      interactions = YAML.safe_load_file(file)["http_interactions"] || []
      [File.basename(file, ".yml"), interactions.count { |i| i.dig("request", "uri").to_s.include?(path_fragment) }]
    end
  end

  # nil unless this interaction's response carries an access token — most do not.
  def self.access_token_lifetime(interaction)
    body = interaction.dig("response", "body", "string").to_s
    return nil unless body.include?("accessToken")

    valid_until = JSON.parse(body).dig("accessToken", "validUntil")
    return nil if valid_until.nil?

    Time.iso8601(valid_until) - Time.httpdate(interaction.fetch("recorded_at"))
  end

  # Anything shaped like a JSON Web Token. KSeF's auth responses carry two — an access token
  # and a refresh token — and the refresh token is a live credential that mints new access
  # tokens until it expires.
  JWT = /eyJ[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]+){0,2}/

  # Every field that has ever carried key material, at any nesting depth.
  SECRET_FIELD = /("(?:token|accessToken|refreshToken|authenticationToken|encryptedToken|
                     encryptedSymmetricKey|initializationVector)"\s*:\s*")([^"]+)(")/x

  # **A pre-signed URL is a credential, and it is not shaped like one.**
  #
  # KSeF hands out the UPO as an Azure user-delegation SAS: the path is public, and the query
  # string *is* the authorisation — `sig` is an HMAC over the rest, and anyone holding it can
  # fetch the document unauthenticated until `se`. DESIGN.md §9.1 lists it among the things that
  # must be scrubbed, `Sessions::InvoiceState#inspect` already redacts it from log lines, and the
  # URI matcher below already strips its parameters. The scrubber was the one place that did not,
  # so two cassettes went into git carrying a live three-day capability (found 2026-08-26).
  #
  # It matched no existing rule and no scanner: a SAS `sig` is not a JWT, not `Bearer`-prefixed,
  # and not a value any machine holds in its environment.
  #
  # The path is kept and the query dropped. Nothing needs the query — the matcher ignores those
  # parameters, and no cassette follows the link (`Client#upo` uses the metered API route) — while
  # the path keeps the field a recognisable URL for anything that parses it.
  SIGNED_URL_FIELD = /("(?:upoDownloadUrl|downloadUrl)"\s*:\s*")([^"?]+)\?[^"]*(")/

  # What a stripped one looks like, so the scanner can tell "scrubbed" from "never had a query".
  #
  # **It stays a query parameter on purpose.** A bare marker would leave the URL with a query
  # that is not a parameter list, and {IGNORED_QUERY} could not strip it — so a request replayed
  # from the scrubbed body would not match the recorded one, whose query still had its
  # parameters. Written as `sig=`, both sides reduce to the bare path and the storage leg is
  # replayable.
  SIGNED_URL_PLACEHOLDER = "sig=<REDACTED>"

  # Every parameter of an Azure user-delegation SAS. The signature is the secret; the rest name
  # the delegation key and its window, and all of them vary per recording — so a URI matcher has
  # to ignore the lot or nothing on the storage host will ever match.
  IGNORED_QUERY = %w[sig se sp sr sv st skoid sktid skt ske sks skv].freeze

  # Headers carrying session state that no replay needs. Dropped outright: this client has no
  # cookie jar — `grep -rn cookie lib/` is empty — so a recorded cookie is dead weight that
  # happens to be a session identifier.
  DROPPED_HEADERS = %w[Set-Cookie Cookie].freeze

  # Anything shaped like a SAS parameter, wherever it appears.
  SIGNED_QUERY = /([?&](?:sig|skoid|sks)=)(?!<)[^&\s"]+/

  # **A request URI is scrubbed too.** Redaction started life on bodies, and the storage leg
  # puts the signature in the request line instead — where nothing was looking.
  def self.redact_url(uri) = uri.to_s.gsub(SIGNED_QUERY) { "#{Regexp.last_match(1)}<REDACTED>" }

  # Redacts what a header may carry and removes what none of them should.
  def self.clean_headers!(message)
    headers = message.headers
    return if headers.nil?

    DROPPED_HEADERS.each { |name| headers.delete(name) }
    headers.each_value { |values| values.map! { |value| redact_header(value) } }
  end

  # Header values are not JSON, so {redact} nearly always no-ops on them; the JWT and
  # signed-URL shapes are what actually appear.
  def self.redact_header(value)
    value.to_s
         .gsub(JWT, "<REDACTED-JWT>")
         .gsub(SIGNED_QUERY) { "#{Regexp.last_match(1)}#{SIGNED_URL_PLACEHOLDER}" }
  end

  # **Why this exists, and why `filter_sensitive_data` was not enough.**
  #
  # A `filter_sensitive_data` block returns *one* string per interaction, and VCR replaces
  # every occurrence of that one string. KSeF's redeem response carries **two** tokens, so a
  # regex capturing the first match scrubbed the access token and left the refresh token — a
  # live credential — sitting in the cassette. Found by inspecting the first successful
  # recording, before it was committed; nothing reached git.
  #
  # This rewrites *every* match instead of the first, which is the property that was missing.
  #
  # **XML bodies are never touched.** The UPO is XML and its bytes must match the
  # `x-ms-meta-hash` KSeF sent — rewriting them would break the integrity check exactly as
  # scrubbing the NIP did (§9.1). No KSeF XML document carries a bearer token; the credentials
  # are all in JSON envelopes and headers.
  def self.redact(body)
    return body if body.nil? || body.empty? || xml?(body)

    body.gsub(SECRET_FIELD) { "#{Regexp.last_match(1)}<REDACTED>#{Regexp.last_match(3)}" }
        .gsub(SIGNED_URL_FIELD) do
          "#{Regexp.last_match(1)}#{Regexp.last_match(2)}?#{SIGNED_URL_PLACEHOLDER}#{Regexp.last_match(3)}"
        end
        .gsub(JWT, "<REDACTED-JWT>")
  end

  # **The XML exemption tests the document, not the first byte.**
  #
  # It was `lstrip.start_with?("<")`, which is wrong in both directions. A UPO served with a
  # byte-order mark is not exempted — `lstrip` does not strip `\uFEFF` — so redaction would
  # rewrite the bytes whose hash KSeF published, which is the exact breakage the exemption
  # exists to prevent. And *any* body beginning with `<` is exempted, so an XML request body
  # carrying a credential passes through untouched. `Auth::Client` POSTs a signed
  # `AuthTokenRequest`, which is XML and is a replayable authentication assertion.
  #
  # Deciding on a declaration or a root element keeps the UPO exempt for the reason it should
  # be — it is a signed document whose bytes are load-bearing — without exempting a body merely
  # because of how it starts.
  def self.xml?(body)
    stripped = body.sub(/\A\uFEFF/, "").lstrip
    stripped.start_with?("<?xml") || stripped.match?(/\A<[A-Za-z_]/)
  end
end

VCR.configure do |config|
  config.cassette_library_dir = RecordedTier::DIR
  # `spec_helper` disables net connect suite-wide; VCR has to hook the same library or the two
  # disagree about who answers a request.
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # **Never `:body`.** `Crypto::Encryptor.generate` draws a random key and IV, and RSA-OAEP
  # padding is randomised on top, so `encryptedSymmetricKey` differs on every run even when the
  # key does not. A body matcher cannot work here and would look like a flaky test rather than
  # an impossible one (§9.1, obstacle 1).
  #
  # The storage host is matched on path alone: the UPO `downloadUrl` is pre-signed, so its query
  # string carries a signature that both expires and is secret.
  #
  # **`record: :none` by default, deliberately.** A missing cassette then fails loudly instead
  # of silently reaching the network and recording whatever it finds — which on this project
  # would mean a test quietly creating a real invoice in TEST. `rake vcr:record` is the only
  # thing that switches it, and that task demands credentials and refuses production.
  config.default_cassette_options = {
    # `rake vcr:record` sets `KSEF_VCR_RECORD`; nothing else does, so an ordinary run cannot
    # record by accident even if a cassette is deleted.
    record: ENV["KSEF_VCR_RECORD"] == "1" ? :all : :none,
    match_requests_on: [:method, VCR.request_matchers.uri_without_param(*RecordedTier::IGNORED_QUERY)]
  }

  RecordedTier::SECRET_ENV.each do |name|
    config.filter_sensitive_data("<#{name}>") { ENV.fetch(name, nil) }
  end

  # Bearer tokens, the KSeF token itself, and the JWTs the auth flow returns.
  config.filter_sensitive_data("Bearer <TOKEN>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end

  # Every token-bearing field and every JWT, in both directions, at any depth — see
  # {RecordedTier.redact} for why a `filter_sensitive_data` block could not do this.
  #
  # Headers are covered too. `filter_sensitive_data` above handles the *request*
  # `Authorization` and nothing else, so every response header was recorded verbatim — which
  # put the WAF's `Set-Cookie` session identifiers into all three cassettes. Nothing in `lib/`
  # reads a cookie (this client keeps no jar), so they are dropped rather than redacted: a
  # value no replay needs should not be in the file at all.
  config.before_record do |interaction|
    interaction.request.body = RecordedTier.redact(interaction.request.body)
    interaction.response.body = RecordedTier.redact(interaction.response.body)
    interaction.request.uri = RecordedTier.redact_url(interaction.request.uri)
    RecordedTier.clean_headers!(interaction.request)
    RecordedTier.clean_headers!(interaction.response)
  end
end

RSpec.configure do |config|
  # Excluded until something is recorded, and **loudly**: `spec/recorded_tier_spec.rb` asserts
  # the tier's own state, and a release check refuses 0.1.0 without cassettes. A tier that
  # silently tests nothing is this project's documented failure mode (the glob that matched no
  # files; the coverage gate `rake` skipped), so the absence is asserted rather than assumed.
  config.filter_run_excluding(:recorded) unless RecordedTier.recorded? || ENV["KSEF_VCR_RECORD"] == "1"

  # Recording reaches the network; replaying must not. VCR hooks WebMock either way, so the
  # allowance is scoped to the recording task alone.
  config.around(:each, :recorded) do |example|
    if ENV["KSEF_VCR_RECORD"] == "1"
      WebMock.allow_net_connect!
      example.run
      WebMock.disable_net_connect!(allow_localhost: false)
    else
      example.run
    end
  end
end
