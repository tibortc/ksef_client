# frozen_string_literal: true

require "json"

# Facts the implementation depends on, asserted against the pinned OpenAPI contract.
#
# Distinct from `artifacts_spec.rb`, which checks that the artifacts have not *changed*.
# These check that the specific claims recorded in `docs/REFERENCE.md` are still true of
# them. The digest test would catch any upstream edit, but it cannot say which recorded
# conclusion the edit invalidated — and a mismatched digest is easy to "fix" by re-pinning
# without re-reading the ledger.
#
# The sections covered here are the ones with **no code yet**. §14.3 and §14.4 are already
# protected by executable assertions because the schemas they concern are in use; §14.1 and
# §14.2 concern crypto and session code that is not written, so without these they would
# rot silently until someone implemented them from a stale conclusion.
RSpec.describe "the pinned OpenAPI contract" do
  let(:spec) do
    JSON.parse(File.read(File.expand_path("fixtures/openapi/open-api.json", __dir__), encoding: "UTF-8"))
  end
  let(:schemas) { spec.fetch("components").fetch("schemas") }

  # docs/REFERENCE.md §14.1. Upstream's prose says the IV is prefixed to the ciphertext;
  # the contract says it is a discrete field, and both reference clients emit bare
  # ciphertext. If this field ever disappears, the prose may have become true and §14.1
  # needs re-reading before any crypto code is written or changed.
  describe "§14.1 — the AES initialisation vector is a discrete field" do
    let(:encryption_info) { schemas.fetch("EncryptionInfo") }

    it "declares initializationVector alongside the wrapped key" do
      expect(encryption_info.fetch("properties").keys)
        .to contain_exactly("encryptedSymmetricKey", "initializationVector", "publicKeyId")
    end

    it "requires it, so it cannot be omitted by folding the IV into the ciphertext" do
      expect(encryption_info.fetch("required")).to include("initializationVector")
    end

    # §10.2: the selector naming which published key did the wrapping.
    it "carries publicKeyId, the key selector of §10.2" do
      expect(encryption_info.fetch("properties")).to have_key("publicKeyId")
    end
  end

  # docs/REFERENCE.md §14.2. The resolution here was wrong once already — drawn from the
  # prose example instead of this contract — so the corrected reading is pinned in place.
  describe "§14.2 — downloadUrl is a pre-signed, unmetered, expiring link" do
    let(:page) { schemas.fetch("UpoPageResponse") }

    it "is a URI, not a path fragment to join with the base URL" do
      expect(page.dig("properties", "downloadUrl", "format")).to eq("uri")
    end

    it "comes with an expiry, so it cannot be treated as a durable reference" do
      expect(page.fetch("properties").keys)
        .to contain_exactly("referenceNumber", "downloadUrl", "downloadUrlExpirationDate")
    end

    # The two that matter most: sending a bearer token to third-party storage would leak
    # it, and the integrity hash is the only check on bytes fetched outside the API.
    it "says not to send the access token, and offers a SHA-256 integrity header" do
      description = page.dig("properties", "downloadUrl", "description")

      expect(description).to include("nie należy")
      expect(description).to include("tokenu dostępowego")
      expect(description).to include("x-ms-meta-hash")
    end

    it "says the link is exempt from API rate limits, which is why it is preferred" do
      expect(page.dig("properties", "downloadUrl", "description")).to include("nie podlega limitom")
    end

    it "still declares the metered fallback route for an expired link" do
      expect(spec.fetch("paths")).to have_key("/sessions/{referenceNumber}/upo/{upoReferenceNumber}")
    end
  end

  # docs/REFERENCE.md §7 item 2, which `lib/ksef/environments.rb` cites directly. Recorded
  # here because it is what made the old §14.2 reading look plausible.
  describe "§7.2 — no path carries an /api prefix" do
    it "declares every path bare, with /v2 living in the server URL" do
      expect(spec.fetch("paths").keys.grep(%r{\A/api})).to be_empty
    end

    it "puts the version in the server URL instead" do
      expect(spec.fetch("servers").map { |s| s["url"] }).to all(end_with("/v2"))
    end
  end
end
