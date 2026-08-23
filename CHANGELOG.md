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

- **`Ksef::UPO` — retrieval, over a connection that has no credential.** A UPO is the legal
  proof that KSeF received an invoice, fetched over an unauthenticated storage link, and
  three properties follow from that.

  **The access token is never sent to a `downloadUrl`.** Those links are pre-signed Azure
  Blob URIs carrying their own authorisation in the query string, and the contract says
  outright not to send the token — it would hand a live KSeF credential to third-party
  storage. Rather than remembering that per call site, `Ksef::HTTP::Connection.storage`
  builds a second connection with **no bearer and no base URL**, so no code path can leak
  one. It also omits JSON encoding and parsing, since a UPO is XML that must survive as the
  exact bytes received.

  **The bytes are archived verbatim.** The Ministry's XAdES signature covers octets, not an
  abstract tree, so even a lossless XML round-trip can produce a document that no longer
  verifies. `UPO::Document` holds the received string and offers no parsed form, no
  `#to_xml` and no re-encode; `#write` uses `binwrite` so a newline translation cannot
  corrupt an archive.

  **`x-ms-meta-hash` is verified** — the only integrity check available on bytes fetched
  outside the API. `#fetch` prefers the unmetered, hash-verified link and falls back to the
  metered route when it expires, which is §14.2's resolution after an earlier reading had it
  backwards. `for_ksef_number` parses the number first, so a mistyped one fails on its CRC-8
  locally rather than as an opaque 404.
- **`Ksef::IntegrityError`** — raised when downloaded bytes do not match the published hash.
  Its own class because the right response is unlike every other error here: *fetch it
  again*. Nothing is wrong with the request, the credentials or the document — the transfer
  was corrupted. Silently archiving corrupt bytes as proof of receipt is the one outcome
  worth refusing loudly.
- **`Ksef::Sessions::Status`** — single-shot session and per-invoice reads, plus
  deadline-bounded waits. Capped exponential backoff (1s, 2s, 4s … 30s, five-minute
  deadline) rather than the reference clients' fixed 1s × 60: at 1/s a single wait spends 60
  of the 1200 requests an hour a context gets, and a 60-second ceiling is far too short for
  a large session. A timeout says the operation has **not failed but outlasted the wait**,
  because conflating the two invites a needless resend.

  **It exposes no list-sessions call at all.** `GET /sessions` is 10 req/min — the tightest
  budget in the API — against 1200/h for the two endpoints polling should use. Omitting the
  method is the simplest way to make that mistake impossible rather than merely discouraged.

  `InvoiceState` surfaces what the endpoint already returns instead of making callers fetch
  it twice: the per-invoice UPO link, and on a duplicate the **original** submission's KSeF
  number and session reference, which is what makes a resend reconcilable. `UpoPage` keeps
  its pre-signed URL out of `#inspect` and `#to_s` — the link carries its own authorisation
  in the query string, so it is a credential — while still exposing it to a caller that asks.
- **Corrected: both `100` and `150` mean "keep polling"**, not `150` alone. The earlier
  reading came from `OnlineSessionUtils.cs`, whose poller returns as soon as the code is
  anything but `150`, and it is wrong on the contract's own wording — `100` is *"przyjęta do
  dalszego przetwarzania"*, accepted for **further** processing, so an invoice sitting there
  is undecided and has no KSeF number. A poller that stops at `100` reports a pending
  invoice as though it were settled.

  The rule is now `code < 200 is in progress` rather than a list of intermediate codes, so a
  code upstream adds later behaves correctly by default. This is deliberately the inverse of
  the treat-the-unknown-as-terminal rule used for *authentication* status, and the asymmetry
  is justified in both places: auth polls without a deadline so it must not loop for ever,
  while session polling is bounded — and "unresolved" is a more honest answer about an
  invoice than "prematurely final". The same rule makes `170` → `200` work for sessions,
  where closing starts asynchronous UPO generation and "closed" is one step short of done.
- **`Ksef::Sessions::Online` — open, send, close.** Stateless and thin, like
  `Auth::Client`: it maps requests and responses and holds no session of its own. Both
  official clients do the same, threading the reference through as a parameter.

  **The `Encryptor` is bound to the `Session`, not passed per send**, and that is the
  decision worth knowing about. The symmetric key is agreed once, at open, and every invoice
  in the session is encrypted under it — so an invoice encrypted with any other key is
  undecryptable at the far end, and the only symptom is per-invoice status `435` arriving
  **asynchronously**, long after the send returned `202`. There is no synchronous error to
  catch. Binding the key to the session makes the mistake unrepresentable rather than merely
  documented, the same move as `Encryptor#seal` returning both digests together.

  Sends `X-KSeF-Feature: upo-v4-3` on open — a header in neither the contract nor any
  upstream prose, but sent by both official clients, which selects the UPO format the session
  produces. This gem bundles `upo-v4-3.xsd` and nothing else, so silence would mean accepting
  a version it might not be able to validate (`docs/REFERENCE.md` §14.6).

  `formCode` comes from the contract rather than from `srodowiska.md`, whose prose misspells
  the PEF system codes and omits `FA_RR (1)` entirely. Reference numbers are shape-checked
  before reaching a URL path.
- **`send_invoice` opens a fresh session per call**, with `client.session { |s| ... }` for
  deliberate batching. Resolves the session-reuse `[VERIFY]` in DESIGN.md §6.5, which the
  facts left open: sessions last 12 hours and take 10 000 invoices, and neither official
  client offers a composite to copy. A reused session is mutable state on a client that must
  be thread-safe; an opened-but-unused session is cancelled with status `440`; and the API
  returning the *original's* KSeF number on a duplicate suggests resends are an expected
  hazard rather than one to make likelier by hiding session state.
- **`Ksef::KsefNumber`** — parses and validates the 35-character identifier KSeF assigns to
  an accepted invoice. CRC-8 with polynomial `0x07`, verified against the Ministry's own
  documented example, which doubles as the golden vector. Checking the checksum locally is
  the point: these numbers get copied between systems and read down telephones, and a CRC-8
  catches exactly those slips, turning a silent lookup failure into a specific error naming
  both the carried and the computed value. `assigned_on` is a `Date` because it is not
  metadata — it is the invoice's **official receipt date**.
- **`Ksef::Auth::AccessToken`** — tracks expiry from the response's `validUntil`, never by
  decoding the JWT: §4.3 excludes the `jwt` dependency and the contract carries `validUntil`
  precisely so no decoding is needed. Refreshes at ~80% of the observed lifetime rather than
  on expiry, so a request never carries a credential that dies mid-flight — on an invoice
  submission, a failure that *might* have been delivered is the situation this gem works
  hardest to avoid. Thread-safe with the staleness check re-run inside the lock, so a burst
  of threads yields one refresh rather than a stampede.
- **`Ksef::Crypto` — the encryption layer.** AES-256-CBC with PKCS#7 for payloads,
  RSA-OAEP with SHA-256 *and* MGF1-SHA-256 for wrapping, and the Ministry's published
  certificates fetched, cached and selected by declared usage. Every parameter is ledgered
  at `docs/REFERENCE.md` §10 from first-tier documentation, not inferred from client
  behaviour.

  **The IV is not prefixed to the ciphertext**, whatever `sesja-interaktywna.md` says. It
  travels once as a discrete field of the session-open request, and each invoice ciphertext
  is bare. There is now a fourth witness against the prose, and it is the sharpest:
  upstream's own worked example pairs a 6480-byte invoice with a 6496-byte ciphertext, which
  is exactly one block of PKCS#7 padding and no room at all for a 16-byte IV (§14.1).

  DESIGN.md §6.4 asked for golden vectors ported from the C# client. **There are none to
  port** — neither reference client commits plaintext/ciphertext pairs. The primitives are
  pinned to their standards instead: **NIST SP 800-38A F.2.5** for AES-256-CBC, byte for
  byte, and **FIPS 180-4** for SHA-256. The two parameters that genuinely could have gone
  wrong are pinned behaviourally: the longest accepted OAEP plaintext is 190 bytes, which
  fixes the digest at SHA-256 without trusting an option name, and a ciphertext made with
  MGF1-SHA-256 provably fails to decrypt under MGF1-SHA-1. That last one matters —
  OpenSSL's MGF1 digest defaults to SHA-1, so naming only `rsa_oaep_md` yields a different
  scheme that fails at the far end and nowhere else.
- **`Ksef::Crypto::PublicKeys`** — `GET /security/public-key-certificates`, cached for an
  hour behind a mutex, with the documented selection rule: filter by usage, require validity
  *at the moment of use*, and prefer the latest `validFrom` where several qualify. The
  endpoint is unauthenticated, so keys can be fetched before any credential exists.

  Two rotation modes must not be conflated. Re-certification keeps the key pair, so
  `publicKeyId` is unchanged; key rotation changes it, and an **emergency** rotation drops
  the old certificate from the list immediately. `#with_key_rotation` implements §10.2's
  recovery for that window — on a `400`/`21470` it re-fetches and re-runs the operation.
  That is remediation and not a blind replay: a 21470 means the request was declined
  outright, and the second attempt carries a *different* key identifier, so DESIGN.md
  §6.7's never-auto-retry-a-POST rule is intact. Any other API error surfaces untouched.
- **`Ksef::Crypto::Encryptor#seal`** returns the ciphertext together with the hash *and*
  size of both the plaintext and the ciphertext. `POST /sessions/online/{ref}/invoices`
  requires all four (§11.1) and hashing the wrong artifact is a silent error only the server
  can catch, so the two digests are produced together rather than left to a caller to pair
  up. Sizes are byte counts, not character counts — the distinction is not academic when
  every KSeF document is full of Polish characters.
- **`Ksef::Auth::Token` — the KSeF-token credential of DESIGN.md §8**, and
  `Auth::Client#submit_ksef_token`. **Both authentication methods now exist.** The token is
  never sent as a bearer: it is RSA-OAEP-encrypted alongside the challenge's own
  `timestampMs`, which the docs describe as a replay nonce — so the method takes a
  `Challenge` object rather than its string, and refuses the string outright. Inventing the
  timestamp locally would fail with nothing to point at.

  Only `Nip` and `InternalId` contexts are offered, though the contract's enum has four: a
  token can only be *issued* in those two, so a token for the other two cannot exist to be
  presented (§4.1). `#to_s` and `#inspect` are redacted; the token is reachable only by
  building the request.
- **`Ksef::CryptoError`** — a new branch of the DESIGN.md §6.7 hierarchy, for "no published
  key is valid for this usage" and for malformed key material. Neither an `ApiError` (the
  request succeeded; the list has nothing usable) nor a `ConfigurationError` (documented as
  local and pre-request). Reasoning recorded at `docs/REFERENCE.md` §10.3, alongside the
  other decisions upstream does not state.
- **Live integration for the crypto module** (`spec/integration/crypto_spec.rb`). Two things
  no offline test can reach: that `certificateId` and `publicKeyId` are derived as §10.2
  claims — recomputed from the real certificates, which matters because the library only
  ever echoes the server's value back — and that KSeF **decrypts** what this gem wrapped,
  since an access token is issued only if the RSA-OAEP ciphertext unwrapped to the right
  `token|timestampMs`. Unlike the XAdES suite this needs no PESEL, so it reuses the stored
  `KSEF_TEST_NIP`/`KSEF_TEST_TOKEN` rather than provisioning a test person.

  **These specs have only ever run against stubs.** They are written, not yet exercised; the
  nightly is their first real run. Nothing in the crypto module is live-verified, and the
  two claims above are what the specs will *test*, not what they have shown.
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
- **Live integration specs, and the nightly schedule enabled.**
  `spec/integration/auth_flow_spec.rb` exercises the real authentication flow against TEST.
  Opt-in twice over — tagged `:integration` *and* excluded unless `KSEF_INTEGRATION=1`,
  because RSpec ANDs exclusion filters with CLI inclusions, so a tag alone would either
  always run or never run. WebMock is re-enabled around each example rather than globally,
  so a failure cannot leave the network open for whatever runs next.

  **DESIGN.md §12.4 is resolved.** Running the bootstrap against TEST established what no
  offline test could: KSeF accepts the XAdES-BES signature this gem produces, the 2.0
  namespace is correct, `/testdata/person` really is unauthenticated, and a self-signed
  certificate is accepted on TEST. Recorded at `docs/REFERENCE.md` §6a.4.
- **`rake auth:bootstrap`** — provisions a TEST credential end to end, retiring the
  workaround `docs/REFERENCE.md` §6a.2 used to describe (a one-time out-of-band mint via
  the official C# client). It invents a checksum-valid NIP and PESEL, registers them
  through the **unauthenticated** `/testdata/person` endpoint — the only reason the chain
  is not circular, since `POST /tokens` needs a session — authenticates by XAdES with a
  self-signed certificate, and mints the token. A real qualified certificate can be
  supplied instead.

  It lives in `tasks/`, so it is never packaged, but it is **not** an untested script:
  every method is covered against stubs. A checksum bug would otherwise surface as an
  opaque rejection from a remote server. It refuses any environment whose `test_data_api?`
  capability is false, so DEMO is refused as well as PROD, and the guard is on the
  capability rather than the name so a `custom` environment cannot slip past.
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
  that had **no code when they were ledgered** — §14.1's discrete IV field, since
  implemented by `Ksef::Crypto`, and §14.2's pre-signed link, which still has none — because
  those are the ones that would otherwise rot unnoticed until someone implemented crypto
  or session handling from a stale conclusion.
- Coverage is now gated on three criteria rather than one, at **line 99, branch 95,
  method 100**. Branch coverage was 83% behind 99% line coverage, so seventeen conditional
  paths were untested; closing the real gaps brought it to 97%, and line coverage to 100%. Fixes uncovered on the way:
  proxy configuration was entirely unexercised, and the `Retry-After` parser's past-date
  and unparseable-value fallbacks had no tests.

### Changed

- The challenge format check moved from `Auth::TokenRequest::CHALLENGE_FORMAT` to
  **`Auth::Challenge::FORMAT`**, with `Challenge.validate_format!` alongside it. Both
  authentication methods consume the same challenge, so the XAdES document and the
  KSeF-token JSON body would otherwise have carried their own copies of one rule.
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

- **Authentication status code `480` was missing.** "Uwierzytelnienie zablokowane" — the
  authentication is blocked on suspicion of a security incident, and the user must contact
  the Ministry. `Ksef::Auth::Status` now names it and says so; before, it fell through to
  "unrecognised status code 480".

  The cause is worth recording, because it is a precedence mistake rather than an oversight.
  `docs/REFERENCE.md` §4.8 had sourced the whole table from `ksef-client-csharp`'s enum, on
  the strength of upstream *prose* saying the full list "will be available in the endpoint's
  technical documentation". The pinned OpenAPI contract — a **first-tier** artifact — states
  the table in full, and carries a code the C# enum does not. Two smaller corrections came
  out of the same reading: `450` collapses **eight** distinct causes rather than four, and
  `400`/`401` are C#-only and not contract codes at all. Now asserted in
  `spec/openapi_contract_spec.rb` so the provenance cannot regress silently.

  The general lesson, now in §4.8: when upstream prose says a fact is undocumented, read the
  OpenAPI descriptions before reaching for a reference implementation.
- **A documentation-consistency pass over the whole repo**, which found no defect that would
  fail a live request but a good deal of drift worth correcting. The notable ones:
  `rake auth:bootstrap` told the operator to store a live KSeF credential as a *repository*
  secret, which is precisely what §6a.3 argues against; the coverage floors existed in three
  places with three different values, one of which would have told a contributor they passed
  when CI fails them; SECURITY.md promised a cassette-scanning spec that did not exist;
  DESIGN.md still instructed the reader to send the 2.1 auth namespace and to take token
  expiry from the JWT `exp` claim, both since ruled against; and `docs/errors.md` was missing
  `Ksef::CryptoError` entirely.

  Also corrected: several documents claimed the certificate flow's live verification covered
  more endpoints than it did. Only four have ever reached KSeF — challenge,
  `xades-signature`, `GET /auth/{ref}` and `redeem`. **`refresh` and `ksef-token` are
  implemented but have never run live**, and the ledger now says so where it previously
  claimed "the whole §4.2 flow works as ledgered".
- **`spec/cassette_hygiene_spec.rb`** — scans every committed VCR cassette for `Bearer `
  headers and for any value held in `KSEF_TEST_TOKEN` / `KSEF_TEST_NIP`, finding them by
  content rather than by path so one saved somewhere unconventional is still caught. No
  cassette exists yet, so it passes vacuously — which is the point of adding it now, since
  SECURITY.md was already promising users that this check ran.
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
- **PESEL is a structured identifier and KSeF enforces it** (§6a.3) — the first fact in the
  ledger whose source is the API's own behaviour rather than a document or a reference
  client. A checksum-perfect PESEL was rejected with `400 [21405] Invalid PESEL format`;
  the first six digits encode a birth date with the century folded into the month field.
  Nothing upstream states this, and no amount of offline verification would have found it.
- **A missing OpenSSL CA bundle looks like a broken server certificate** (§6a.5). Recorded
  because the error names the wrong thing entirely and the tempting fix — disabling
  verification — is a hard-rule violation.
- **The PESEL checksum is now recorded** at §6a.3 — needed to invent a test person, and
  confirmed the way §6a.1 confirmed the NIP algorithm: it validates every PESEL the
  upstream documentation ships and rejects those values with the check digit altered.
  §6a.3 also states the NIP check digit precisely, because it is easy to get backwards —
  it *is* the weighted sum `mod 11`, not `11 - (sum mod 11)`.
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
