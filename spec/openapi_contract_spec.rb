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
# These cover the sections whose conclusions had no code to protect them when they were
# ledgered. §14.3 and §14.4 were always guarded by executable assertions, because the
# schemas they concern are in use. §14.1 is now implemented by `Ksef::Crypto` and guarded
# there too, so these assertions are its second line of defence; **§14.2 still has no code
# at all**, and until the session layer lands these are the only thing keeping it from
# rotting into a stale conclusion someone later implements.
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

    # The fourth, arithmetic, witness against the prose — found 2026-08-23 and recorded in
    # §14.1. The worked example on the send-invoice operation pairs a 6480-byte plaintext
    # with a 6496-byte ciphertext. 6480 is a whole number of AES blocks, so PKCS#7 adds
    # exactly one block; a 16-byte IV prefix would have made it 6512.
    it "pairs plaintext and ciphertext sizes that leave no room for a prefixed IV" do
      example = spec.dig("paths", "/sessions/online/{referenceNumber}/invoices", "post",
                         "requestBody", "content", "application/json", "example")
      plain = example.fetch("invoiceSize")
      encrypted = example.fetch("encryptedInvoiceSize")

      expect(plain % 16).to eq(0)
      expect(encrypted - plain).to eq(16)
    end

    # The document that describes the encryption names CBC and PKCS#7 outright, so the
    # cipher choice of §10.1 is stated by the contract and not only by the prose.
    it "names AES-256-CBC with PKCS#7 on the invoice payload itself" do
      description = schemas.dig("SendInvoiceRequest", "properties", "encryptedInvoiceContent", "description")

      expect(description).to include("AES-256-CBC")
      expect(description).to include("PKCS#7")
    end
  end

  # docs/REFERENCE.md §10.2. `Ksef::Crypto::PublicKeys` selects on `usage` and sends
  # `publicKeyId` back; both facts come from here.
  describe "§10.2 — the published encryption certificates" do
    it "declares exactly the two usages the client selects between" do
      expect(schemas.dig("PublicKeyCertificateUsage", "enum"))
        .to contain_exactly("KsefTokenEncryption", "SymmetricKeyEncryption")
    end

    it "requires the usage list and the validity window the selection rule needs" do
      expect(schemas.dig("PublicKeyCertificate", "required"))
        .to include("certificate", "certificateId", "publicKeyId", "usage", "validFrom", "validTo")
    end

    # Base64 of a SHA-256 is always 44 characters, which is what fixes the field width —
    # and what makes `publicKeyId` recognisable as a digest rather than an opaque id.
    it "fixes publicKeyId at the 44 characters a base64 SHA-256 occupies" do
      selector = schemas.dig("EncryptionInfo", "properties", "publicKeyId")

      expect([selector["minLength"], selector["maxLength"]]).to eq([44, 44])
      expect(schemas.dig("Sha256HashBase64", "minLength")).to eq(44)
    end

    it "leaves the certificate list unauthenticated, so keys can be fetched before login" do
      expect(spec.dig("paths", "/security/public-key-certificates", "get")).not_to have_key("security")
      expect(spec).not_to have_key("security")
    end
  end

  # docs/REFERENCE.md §4.5 and §10.1 — the KSeF-token authentication payload.
  describe "§4.5 — the encrypted KSeF token" do
    it "documents RSA-OAEP with SHA-256 over token|timestamp in milliseconds" do
      description = spec.dig("paths", "/auth/ksef-token", "post", "description")

      expect(description).to include("RSA-OAEP")
      expect(description).to include("SHA-256")
      expect(description).to include("token|timestamp")
      expect(description).to include("milisekund")
    end

    it "requires the challenge, the context and the encrypted token" do
      expect(schemas.dig("InitTokenAuthenticationRequest", "required"))
        .to contain_exactly("challenge", "contextIdentifier", "encryptedToken")
    end

    # The remediation path of §10.2 keys off this code, so its meaning is pinned here.
    it "declares 21470 for a withdrawn or unknown key identifier" do
      expect(spec.dig("paths", "/auth/ksef-token", "post", "responses", "400", "description"))
        .to include("21470")
    end
  end

  # docs/REFERENCE.md §4.8. The ledger originally sourced these codes from the C# client's
  # enum and said the contract did not state them. It does — and reading it added 480, which
  # the C# enum lacks. Pinned here so the provenance cannot quietly regress a second time.
  describe "§4.8 — the contract states the authentication status codes" do
    let(:table) do
      schemas.dig("AuthenticationOperationStatusResponse", "properties", "status", "description")
    end

    it "carries a code table, not merely prose about two of them" do
      expect(table.scan(/^\| (\d{3}) \|/).flatten.map(&:to_i).uniq)
        .to contain_exactly(100, 200, 415, 425, 450, 460, 470, 480, 500, 550)
    end

    # The one code a client must not treat as transient.
    it "declares 480 as a security block, which is why it is not retryable" do
      expect(table).to match(/^\| 480 \|/)
      expect(table).to include("Podejrzenie incydentu bezpieczeństwa")
      expect(Ksef::Auth::Status::DESCRIPTIONS).to have_key(480)
    end

    # §4.8 used to say four; the contract lists eight, which is why `#explain` prefers the
    # server's own description over any table of ours.
    it "collapses eight distinct causes into 450" do
      expect(table.scan(/^\| 450 \|/).size).to eq(8)
    end

    it "does not declare 400 or 401, so those two are C#-only" do
      expect(table).not_to match(/^\| 40[01] \|/)
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
