# frozen_string_literal: true

require "vcr"

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

  # Anything shaped like a JSON Web Token. KSeF's auth responses carry two — an access token
  # and a refresh token — and the refresh token is a live credential that mints new access
  # tokens until it expires.
  JWT = /eyJ[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]+){0,2}/

  # Every field that has ever carried key material, at any nesting depth.
  SECRET_FIELD = /("(?:token|accessToken|refreshToken|authenticationToken|encryptedToken|
                     encryptedSymmetricKey|initializationVector)"\s*:\s*")([^"]+)(")/x

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
    return body if body.nil? || body.empty? || body.lstrip.start_with?("<")

    body.gsub(SECRET_FIELD) { "#{Regexp.last_match(1)}<REDACTED>#{Regexp.last_match(3)}" }
        .gsub(JWT, "<REDACTED-JWT>")
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
    match_requests_on: [:method, VCR.request_matchers.uri_without_param(*%w[sig se sp sr sv st])]
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
  config.before_record do |interaction|
    interaction.request.body = RecordedTier.redact(interaction.request.body)
    interaction.response.body = RecordedTier.redact(interaction.response.body)
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
