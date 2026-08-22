# Changelog

All notable changes to this project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Every release entry states the **KSeF API version** and **FA schema revision** it
targets. The Ministry ships changes continuously, so users must be able to answer "which
gem version for which API state".

## [Unreleased]

**Targets:** KSeF API 2.0 · FA(3) `1-0E` · upstream `CIRFMF/ksef-api@1c34fe27`

### Added

- `rake fa3:generate` — codegen producing committed `lib/ksef/fa3/generated/`: 59 content
  models and 21 enumerations read from the pinned FA(3) XSD. Hand-written models consume
  this for element ordering, occurrence rules and enum membership.
- `rake fa3:verify` — regenerates and fails on any byte difference, so a non-deterministic
  generator or a stale `generated/` breaks the build. Runs in the default task and on every
  CI matrix leg.
- Pinned `AuthTokenRequest` schemas (auth v2-0 and v2-1) ahead of the certificate auth flow.
- **FA(3) models and serializer.** A plain `VAT` invoice can be described with English
  keyword arguments and serialised to schema-valid XML. `Ksef::FA3::Invoice`,
  `Subject`, `Line`, `Address`, plus `NIP` checksum validation, `VatRate` bucket mapping and
  centralised `Formatting`. Both rounding strategies from DESIGN.md §7.3 are implemented.
- **`Ksef::FA3::Validator`** — offline XSD validation against the bundled schema. The
  schema's one remote `xsd:import` is redirected in memory, so validation needs no network
  and the pinned file stays byte-identical.
- The serializer reads element order from the generated metadata rather than hand-listing
  it, and raises on element names the schema does not define at that position instead of
  dropping them silently.
- **`Ksef::Auth::Client`** — the six HTTP calls of the authentication flow, with typed
  responses (`Challenge`, `Initiation`, `OperationStatus`, `Tokens`, `TokenInfo`) and a
  poller. Deliberately thin: it maps requests and responses and nothing else. Only
  `wait_until_complete` has policy, and it has **no timeout by default** — on DEMO and PROD
  the operation legitimately stays "in progress" while the certificate's status is checked
  with its issuer over OCSP/CRL, so a fixed deadline would report failure for
  authentications that were about to succeed.
- **`Ksef::Auth::Status`** — the eleven authentication status codes. These are not HTTP
  statuses; they arrive inside a 200 response. An unrecognised code is treated as
  **terminal**, because assuming otherwise polls a dead operation for ever, and elapsed
  time cannot distinguish "still legitimately 100" from "stuck".
- `TokenInfo` redacts **both `#inspect` and `#to_s`**. Redacting only `#inspect` leaves the
  leak that actually happens — interpolating a token into a log line. Extracting the value
  is an explicit `#token` call, and `Auth::Client` does that when setting the header.
- **`Ksef::Auth::Signer`** — the XAdES-BES enveloped signature for
  `POST /auth/xades-signature`, built on Nokogiri and stdlib `openssl` with no new
  dependency. Every algorithm is from the Ministry's published allow-list, and the shape is
  corroborated against both official clients. Its specs recompute each digest and verify
  the `SignatureValue` **without reusing any of the signer's own code**, so a test cannot
  pass by agreeing with a bug; they also assert that tampering with the payload, the
  signing time, or the signature itself is detected, and that the result validates against
  the pinned xmldsig schema.

  It signs a String and returns a String on purpose. A digest over "the document" has to
  match what the verifier computes after parsing the bytes sent, and Nokogiri pretty-prints
  on output without adding text nodes to the tree — so an in-memory tree and its serialised
  form can canonicalise differently. Output is emitted with `FORMAT` off; re-indenting after
  signing would invalidate every signature while leaving it internally consistent.
- **`Ksef::Auth::SignatureTemplate`** and **`Ksef::Auth::Xades`** — the signature XML and
  the algorithm vocabulary, split out so that rendering and cryptography are separable.
- **`Ksef::Auth::TokenRequest`** — the `AuthTokenRequest` document, step 2 of the
  authentication flow. Sends the **2.0** namespace by default, validates the challenge
  format locally
  before a signature is spent on it, and emits the `ContextIdentifier` choice and the
  optional `AuthorizationPolicy` in schema order regardless of the caller's argument
  order. A spec compares the generated document against upstream's own pinned example,
  canonicalised, so the implementation is tied to an artifact rather than to a reading of
  one.
- **`Ksef::Auth::AuthorizationPolicy`** — the client-IP whitelist as its own value object,
  since the schema treats it as a distinct structure with its own rules (three list kinds,
  each capped at ten, fixed order, mandatory `AllowedIps` wrapper). IP *values* are left
  to the schema rather than re-validated in Ruby, which would mean maintaining a second
  and divergent source of truth.
- Pinned the **W3C xmldsig and ETSI XAdES v1.3.2/v1.4.1 schemas** that upstream
  redistributes in its PEF bundle, so the signature namespaces come from an artifact
  rather than from memory. All three compile offline — their imports are relative, so
  unlike the FA(3) schema they need no `schemaLocation` rewrite — which means the signer
  will get real structural validation. Kept under `spec/fixtures/`, not `lib/`: validating
  a signature is a test-time concern, and these are W3C/ETSI documents whose terms are not
  the repository's MIT licence that §1.2 relied on for bundling the FA schemas.
- **`Ksef::Auth::Validator`** — offline XSD validation for auth documents, mirroring
  `Ksef::FA3::Validator`. Validates a document in either namespace, taking the rules from
  v2.1's file with its target namespace rewritten in memory, because v2.0's file cannot be
  compiled at all. A namespace that is not a known schema version is refused rather than
  validated against itself.
- **`Ksef::FA3.build` — the keyword DSL of DESIGN.md §8.** That section's snippet now runs
  verbatim and produces schema-valid FA(3) XML, so the README's headline example is no
  longer aspirational. The DSL accepts the English shorthand from the spec (`qty:`,
  `vat:`) alongside the canonical names, and coerces an address given as a Hash or as an
  already-formatted String. It is a thin front end over the existing value objects —
  every computation and every schema default stays in `Invoice`, so there is one
  implementation of each rule rather than two.

  Unknown or misspelled keys **raise**, naming what was permitted, on the same reasoning
  as the serializer's treatment of unknown element names: the alternative is an invoice
  that is silently missing a field. Passing both a shorthand and its canonical name
  (`qty:` and `quantity:`) is an error rather than a silent last-one-wins. Single-value
  fields set twice do take the later value, which is what a builder should do.
- **Pinned the normative subset of upstream's prose documentation** (`docs/upstream/`, 19
  files) plus the UPO schema and its six worked examples, all at the same
  `CIRFMF/ksef-api@1c34fe27` already used for the OpenAPI contract and FA schemas. The
  repository holds 77 files and only 4 had been pinned; most of what the ledger listed as
  "unverified" turned out to be documented prose nobody had read. Newly ledgered from
  first-tier sources: crypto parameters, XAdES signature requirements, online session
  semantics, the UPO format, per-endpoint rate limits, size limits, and the KSeF number
  structure. Four of the five open items in `docs/REFERENCE.md` §9 are now closed,
  including both that were marked as blocking.
- `docs/REFERENCE.md` §14 — a new section for **contradictions within upstream's own
  sources**, kept separate from §7's divergences from this project's design document. Four
  are recorded, each with the resolution and the evidence for it.
- `spec/openapi_contract_spec.rb` — asserts the ledger's claims against the pinned
  contract, rather than only that the contract has not changed. It covers the two findings
  that have **no code yet** (§14.1's discrete IV field, §14.2's pre-signed link), because
  those are the ones that would otherwise rot unnoticed until someone implemented crypto
  or session handling from a stale conclusion.
- Coverage is now gated on three criteria rather than one, at **line 99, branch 95,
  method 100**. Branch coverage was 83% behind 99% line coverage, so seventeen conditional
  paths were untested; closing the real gaps brought it to 97%, and line coverage to 100%. Fixes uncovered on the way:
  proxy configuration was entirely unexercised, and the `Retry-After` parser's past-date
  and unparseable-value fallbacks had no tests.

### Changed

- **`bigdecimal` constraint widened from `~> 3.1` to `>= 3.1, < 5`.** The old constraint
  made this gem uninstallable alongside bigdecimal 4, which has been out since 2026-03.
  A library should not force that choice on its users over an arithmetic dependency.
- **Certificate/XAdES authentication moved from 0.3 into 0.1.** A KSeF token can only be
  issued after a one-time XAdES authentication, so a token-only client cannot bootstrap a
  credential from nothing.
- The prior-art claim in DESIGN.md §1 ("there is no Ruby SDK") is withdrawn: `ksef-rb`
  exists and is a working KSeF 2.0 client. This gem's distinction is FA(3) authoring and
  validation rather than transport alone.

### Fixed

- `spec.files` globbed only the FA(3) schema directory, so schemas added elsewhere under
  `lib/` would not have shipped — a failure that would appear only in the packaged gem.

### Notes

Two further upstream defects found while implementing authentication, both recorded with
evidence in `docs/REFERENCE.md` §14.4. The root cause is shared: **XML Schema regular
expressions are implicitly anchored, and `^` / `$` are literal characters, not anchors.**

- **Neither official client validates the request locally, and both send the 2.0
  namespace.** C# serialises with `XmlSerializer` and no schema; Java marshals with JAXB
  and never calls `setSchema`. The bundled XSD is a codegen input, not a runtime check, so
  the defects below never fire for them — they emit the real identifier and let the server
  decide. This gem now does the same, and sends 2.0. The Java client even ships its own
  edited copy of the 2.0 schema with the IP patterns repaired but `TNipVatUE` and
  `TPeppolId` left broken, which independently confirms those two are defective.
- **The authentication status codes are now recorded** at `docs/REFERENCE.md` §4.8, from
  the reference implementation — the Ministry's prose names only two of the eleven and says
  the rest "will be available in the endpoint's technical documentation". This narrows, but
  does not close, the open error-code catalogue in §9.
- **A signed `AuthTokenRequest` can never be schema-valid.** The API requires an enveloped
  signature; the schema defining the document declares a closed sequence with no
  `xsd:any`, so that signature is an unexpected element. Both requirements are upstream's
  and they contradict each other. `Signer#sign` therefore validates *before* signing by
  default, which also catches a malformed document before a signature is spent on it.
- **`schemat_auth_v2-0.xsd` does not compile as a schema at all.** Its IP patterns use
  `\b`, which XSD regex has no concept of, so libxml2 rejects the whole file rather than
  those facets. Anyone validating against v2.0 gets a compilation failure, not a
  validation result. Only v2.1 is usable, and it rewrote all three patterns correctly.
- **Two of v2.1's four context identifiers cannot hold their real values.** `TPeppolId`'s
  pattern is written `^P[A-Z]{2}[0-9]{6}$`, so it matches only a value that literally
  starts with `^` and ends with `$`; `TNipVatUE`'s ends with a stray `$`. Upstream's own
  documented example value for `NipVatUe` fails the schema that defines it. The natural
  value is emitted regardless and local validation is reported as advisory for those two
  types — a KSeF token can only be issued in a `Nip` or `InternalId` context anyway, and
  both of those validate cleanly.

Three upstream inconsistencies found while pinning the documentation, each of which would
have produced a working-looking client that fails in practice. All are recorded with
evidence in `docs/REFERENCE.md` §14.

- **The AES initialisation vector is not prefixed to the ciphertext**, despite
  `sesja-interaktywna.md` saying it is. The pinned OpenAPI contract carries the IV as a
  discrete `EncryptionInfo.initializationVector` field, and both the C# and Java reference
  clients emit bare ciphertext. Following the prose yields payloads KSeF cannot decrypt.
- **All six of upstream's UPO examples fail upstream's own UPO schema**, each with the same
  single error: `NazwaPodmiotuPrzyjmujacego` is `fixed="Ministerstwo Finansów"` in the XSD,
  but TEST issues `"Ministerstwo Finansów - środowisko testowe (TE)"`. A client that
  strictly validates a received UPO would reject every UPO that TEST issues.
- **`upo.pages[].downloadUrl` is a pre-signed storage link, not a path to join.** The
  contract declares it `format: uri`, generated per status query, expiring at
  `downloadUrlExpirationDate`, **exempt from API rate limits**, and served with an
  `x-ms-meta-hash` SHA-256 integrity header — and says the access token must *not* be sent
  to it. Both reference clients implement it that way; C# passes `token: null` explicitly.
  Given how tight the session budgets are, this unmetered path is the better default, with
  `GET /sessions/{ref}/upo/{upoRef}` as the fallback once a link expires.

## [0.1.0.rc1] — 2026-08-22

**Targets:** KSeF API 2.0 · FA(3) `1-0E` (`kodSystemowy` `FA (3)`, variant 3)
· upstream `CIRFMF/ksef-api@1c34fe27` (2026-07-21)

> **Prerelease. Not usable for invoicing.** This release exists to verify the trusted
> publishing pipeline and to claim the gem name. It contains the transport foundations
> only — authentication, encryption, sessions and the FA(3) builder are not implemented,
> so no invoice can be sent yet. Prereleases are not installed by `gem install
> ksef_client`; you would have to ask for this version explicitly.

### Added

- Pinned upstream artifacts with SHA-256 manifest: the OpenAPI 3.0.4 contract
  (78 paths, 302 schemas) and the FA(3) XSD with its three base schemas. Verified on
  every test run and by `rake verify:artifacts`.
- `docs/REFERENCE.md`, the verification ledger — every externally sourced fact with its
  source URL and retrieval date.
- `Ksef::Environments` with TEST, DEMO and PROD base URLs verified against each
  environment's own OpenAPI document, plus a `custom(base_url:)` escape hatch that
  requires HTTPS.
- `Ksef::Configuration` — frozen at construction for thread safety, with a redacting
  `#inspect`, duck-typed logger validation, and rejection of unknown options.
- `Ksef::RetryPolicy` — idempotent-only retries with capped exponential backoff, honouring
  `Retry-After` unclamped. Invoice submission is never auto-retried.
- Full error hierarchy under `Ksef::Error`, including `AuthorizationError` (403, with
  `reason_code` and the structured `security` payload) and `ResourceGoneError` (410).
- `Ksef::ProblemDetails` — normalises both KSeF error envelopes (`application/problem+json`
  and the deprecated `application/json` shapes) and degrades gracefully on non-JSON bodies.
- `Ksef::HTTP::Connection` — Faraday connection factory with TLS 1.2 floor, verification
  always on, and error mapping.
- `Ksef::HTTP::SystemWarning` — surfaces the `X-System-Warning` advisory header the API
  sets on successful responses.
- Requests send `X-Error-Format: problem-details`, opting into RFC7807 error bodies.
  This is opt-in per request, not selected by content negotiation: without the header the
  API returns the deprecated envelopes, which carry no `traceId`, no structured `errors[]`
  codes on 400 and no `reasonCode` on 403.
- CI: test matrix across Ruby 3.2/3.3/3.4/4.0/head, nightly TEST integration, and a
  tag-triggered release workflow using RubyGems Trusted Publishing.

### Notes

- The `ksef-docs` repository named in the design document does not exist; all upstream
  documentation, the OpenAPI spec and the FA schemas live in `CIRFMF/ksef-api`.
- Endpoint paths carry no `/api` prefix — the base URL includes `/v2` and paths are
  appended bare.
- The FA(3) schemas are MIT-licensed by Ministerstwo Finansów, so they are bundled with
  the gem rather than fetched at first run.
- **The Ruby 3.2 floor is retained despite 3.2 reaching EOL upstream**, as a deliberate
  exception to the EOL-drop policy (DESIGN.md §3). The full suite is verified green on
  3.2.11. The EOL-drop rule governs 3.3 and later series.
