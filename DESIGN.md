# `ksef_client` — Design Document

| | |
|---|---|
| **Status** | Approved for implementation |
| **Date** | 2026-08-21 |
| **Deliverable** | Ruby gem `ksef_client`, published to RubyGems.org |
| **Scope of first release (0.1.0)** | Full KSeF 2.0 transport client **and** full FA(3) invoice builder |
| **Audience of this document** | The implementing agent (Claude Code session) and human reviewers |

---

## 0. How to use this document (read first, agent)

1. This document contains **decisions** (locked — do not relitigate without flagging) and **facts**. Facts are marked either *(verified 2026-08)* or **[VERIFY]**.
2. **[VERIFY]** items MUST be confirmed against the authoritative sources in §2 *before* the code that depends on them is written. Record every verified fact (value + source URL + date) in `docs/REFERENCE.md` in the repo. Never invent endpoint paths, XML element names, namespace URIs, or cryptographic parameters — if a detail is not in this document and not verifiable from §2 sources, stop and flag it.
3. Work in the milestone order of §11. Each milestone has acceptance criteria; do not start the next until the current one's criteria pass.
4. The code snippet in §8 is the public API contract. It must run verbatim (env vars aside) against the KSeF TEST environment before 0.1.0 ships.
5. Prohibitions summary (details throughout): no dependency additions beyond §4.3 without flagging; no upper bound on `required_ruby_version`; no secrets in logs or VCR cassettes; no auto-retry of non-idempotent requests (sole exception: the opt-in `21470` key-rotation remediation, `docs/REFERENCE.md` §10.2); no hand edits to `lib/ksef/fa3/generated/`; never point tests at the PROD environment.

---

## 1. Purpose and context

**KSeF** (Krajowy System e-Faktur) is Poland's national e-invoicing system. Invoicing through it is a legal obligation: since **2026-02-01** for taxpayers with 2024 gross sales above 200M PLN, and since **2026-04-01** for essentially everyone else *(verified 2026-08)*. An "invoice" in KSeF is an XML document conforming to the **FA(3)** logical structure (XSD), submitted over the **KSeF API 2.0** REST interface. The 1.0 API was switched off on 2026-02-01; 2.0 is the only API *(verified 2026-08)*.

Key API 2.0 characteristics *(verified 2026-08)*:

- REST with a published **OpenAPI (JSON) contract**, intended for code generators and contract validation.
- **JWT-based authentication**, initiated by a challenge; the challenge is valid for **10 minutes**.
- Two auth methods: (a) **KSeF token** — encrypt `token|timestampMs` with RSA-OAEP using a KSeF public key; (b) **qualified signature** — an XAdES-signed `AuthTokenRequest` (enveloped or enveloping form; detached is rejected).
- **Encryption of invoice payloads is mandatory in all modes** (interactive and batch), unlike API 1.0 where it was batch-only.
- Unified session initialization for **interactive (online)** and **batch** modes; batch submissions report errors **per invoice** instead of rejecting the whole package.
- Three environments: **TEST** (public, includes a helper API for generating test data), **DEMO** (pre-production), **PROD**.
- The Ministry of Finance maintains official open-source SDKs in **C#** and **Java** (GitHub org `CIRFMF`); the C# client is actively released (2.7.x as of 2026-08). There is **no Ruby SDK** — that is the gap this gem fills.

**Prior art in Ruby (revised 2026-08-22).** An earlier draft of this section claimed there was no Ruby SDK. That is false and the claim is withdrawn. RubyGems carries:

- `ksef` — abandoned 0.1.0 skeleton (June 2025), hence our name choice.
- **`ksef-rb`** — Michał Siwek, MIT, 0.1.3 as of 2026-07-13, ~626 downloads. A genuine KSeF 2.0 client built against the same OpenAPI spec and the same CIRFMF reference clients, supporting **both** KSeF-token and certificate authentication.

`ksef-rb` is ahead of us on authentication and on shipping. Where it stops is FA(3) *authoring*: it carries an `invoice_header` and invoice transport, but no schema-backed builder, no bundled XSD and no validation — the caller supplies the XML.

**The gap this gem fills is therefore narrower and more specific than "there is no Ruby SDK":** it is the only Ruby client that can *author and validate* an FA(3) document rather than only transport one. That is also the larger half of the work, and the half where getting it wrong produces rejected or silently malformed invoices. `ksef-rb` is MIT-licensed and worth reading before implementing the crypto and session layers — it has solved the same problems.

---

## 2. Authoritative sources and verification protocol

Consult in this order of authority:

1. **Official integrator documentation portal:** https://ksef.podatki.gov.pl/ksef-na-okres-obligatoryjny/wsparcie-dla-integratorow/ — OpenAPI spec (JSON), integration handbook, FA(3) schema publications.
2. **`CIRFMF` GitHub org:** https://github.com/CIRFMF — especially `ksef-docs` (developer compendium incl. environment list and crypto docs), `ksef-api` (integration guide), `ksef-client-csharp` and `ksef-client-java` (reference implementations).
3. The **OpenAPI JSON spec** downloaded from (1): the single source of truth for endpoint paths, request/response models, and error payload shapes.
4. The **FA(3) XSD** downloaded from (1): the single source of truth for element names, ordering, types, and enumerations.

**Protocol:** at the start of Phase 1, download and commit pinned copies of the OpenAPI spec (`spec/fixtures/openapi/`) and the FA(3) XSD (`lib/ksef/fa3/schema/`), recording source URL, retrieval date, and any published version/hash in `docs/REFERENCE.md`. All **[VERIFY]** items below resolve against these pinned artifacts or the `ksef-docs` pages; when the pinned artifacts and this document disagree, the artifacts win — update `docs/REFERENCE.md` and note the divergence in the PR description.

**[VERIFY] list (non-exhaustive):**

- Base URLs of TEST / DEMO / PROD (from the "Środowiska KSeF API 2.0" document in `ksef-docs`).
- Exact endpoint paths and payload schemas for: auth challenge, token-based auth, XAdES auth, token redemption/refresh, public-key certificates, session open/close/status, invoice send/status, UPO retrieval, invoice download/query. (Known approximate shapes: `POST /api/v2/auth/challenge`, `POST /api/v2/auth/xades-signature`; public keys via a `security/public-key-certificates` resource — confirm all against the OpenAPI spec.)
- Cryptographic parameters: symmetric cipher for invoice payloads (expected AES-256, CBC with PKCS#7 padding and IV conventions per docs — confirm mode, padding, IV placement), RSA-OAEP digest/MGF parameters for key wrapping and for token encryption, and which published certificate is used for which purpose (the docs distinguish usage, e.g. a token-encryption key).
- FA(3): XSD namespace URI, `KodFormularza`/`WariantFormularza` header values, schema version string, and the complete P_13_x/P_14_x rate-bucket ↔ VAT-rate mapping.
- JWT lifetime and refresh mechanics; session lifetime; rate limits and their HTTP signaling (needed for §6.7 retry policy).
- UPO document format and how it is fetched per session vs per invoice.

---

## 3. Product decisions (locked)

| Decision | Value | Rationale (short) |
|---|---|---|
| Gem name | `ksef_client` | `ksef` is squatted; underscore convention for multi-word names |
| Root namespace | `Ksef` (`Ksef::Client`, `Ksef::FA3`, …) | Ergonomics; gem-name/namespace mismatch handled in §5.3 |
| License | MIT | Ecosystem norm; matches official SDKs |
| 0.1.0 scope | Transport client + **full** FA(3) builder (all invoice types) | Decided: complete "KSeF in Ruby" solution, not an API wrapper |
| Ruby floor | `>= 3.2.0`, **no upper bound, ever** | Rails 8.0 floor is 3.2 → large install base of compliance-driven laggards; 3.2 has `Data.define`. Ruby 4.0 (2025-12-25) proved upper bounds are landmines |
| Development/CI primary | Ruby 4.0 (current patch, 4.0.6 as of writing) | Strictest interpreter surfaces un-bundled-stdlib and deprecation issues locally |
| CI matrix | 3.2, 3.3, 3.4, 4.0, head (head = allow-failure) | Full supported range + early warning for 4.1 (expected 2026-12) |
| Rubies | MRI only; JRuby/TruffleRuby "untested, PRs welcome" | Crypto needs precise OpenSSL OAEP parameterization |
| Version-support policy | Support all non-EOL MRI series; drop EOL rubies in **minor** releases with changelog note. **Exception: the 3.2 floor is retained past its EOL — see note below** | `required_ruby_version` resolves at install time, so old rubies keep last compatible release |

**Note on the 3.2 floor and EOL (decided 2026-08-22).** Ruby 3.2 reached EOL in 2026, which
under the version-support policy above would mean dropping it. **It is deliberately kept.**
The audience for this gem is Polish tax-compliance software, where upgrade cycles are slow
and the Rails 8.0 floor of 3.2 defines a large real install base; dropping the floor would
exclude exactly the users the gem exists to serve, for no technical gain. The EOL-drop rule
therefore governs *future* series (3.3 and later), not the 3.2 floor. Revisit only if
supporting 3.2 starts forcing genuine compromises in the implementation.

Because RuboCop's `TargetRubyVersion` verifies only syntax and **not** API availability, a
method added in 3.3 or later passes both lint and a green run on the development Ruby, then
fails on a user's interpreter. The `3.2` leg of the CI matrix (§10) is what mechanically
catches this, on every push. The local 3.2 run (§10 pre-release ritual, procedure in
CLAUDE.md) exists to catch it before CI does — cheap, and worth running at each milestone.

**Non-goals (0.x):** no Rails engine or generators; no ActiveRecord integration; no KSeF 1.0 / FA(2) support; no async/concurrent client (thread-safe sync only); no invoice PDF rendering; no JRuby support; no GUI/CLI beyond development rake tasks.

---

## 4. Toolchain, dependencies, and Ruby idioms

### 4.1 Files at repo root

```
.ruby-version        → 4.0.6            (bump patch as released)
.rubocop.yml         → TargetRubyVersion: 3.2; rubocop + rubocop-rspec + rubocop-rake
Gemfile.lock         → GITIGNORED (library convention; CI resolves fresh per matrix ruby)
```

### 4.2 Gemspec essentials

```ruby
spec.required_ruby_version = ">= 3.2.0"          # never add an upper bound
spec.metadata["rubygems_mfa_required"] = "true"
spec.metadata["changelog_uri"] = "<repo>/blob/main/CHANGELOG.md"
# summary: "Ruby client for KSeF 2.0 (Polish National e-Invoice System) with an FA(3) invoice builder"
```

### 4.3 Dependency policy

Runtime (0.1.0) — exactly these, pessimistically constrained at current majors:

| Gem | Why | Notes |
|---|---|---|
| `faraday` (~> 2) | HTTP | default `net_http` adapter; keep adapter-swappable |
| `nokogiri` | XML build/parse, XSD validation, canonicalization groundwork | |
| `bigdecimal` | All monetary amounts | **Must** be declared: bundled (not default) gem since Ruby 3.4. Constrained `>= 3.1, < 5` — see the note below |
| `zeitwerk` (~> 2) | Autoloading | |

**Note on "pessimistically constrained at current majors" (revised 2026-08-22).** Read
literally, that would mean `bigdecimal ~> 4.0` now that 4.x is current. It is instead
`>= 3.1, < 5`, spanning both majors, because this is a **library**: `~> 3.1` would make
the gem uninstallable for any application already on bigdecimal 4, and `~> 4.0` would
exclude everyone still on 3. Neither is a decision a library should force on its users
over a dependency it uses only for arithmetic. The upper bound stays, so this is not a
precedent for unbounded runtime dependencies — and it has nothing to do with the separate
rule against bounding `required_ruby_version` (§3).

Apply the same reasoning to the other three when their majors turn over: prefer spanning
to pinning unless a major genuinely breaks us.

Deliberately **excluded** — do not add:

- `base64` gem → use `[data].pack("m0")` / `str.unpack1("m0")` (strict, zero-dep).
- `logger` / `ostruct` requires → both are bundled gems since Ruby 4.0. Accept any logger-duck object in config; use `Data.define` instead of OpenStruct.
- `jwt` → treat the access token as an opaque bearer string; take expiry from the API response. If a claim must ever be read, decode the payload segment manually (no signature verification needed client-side).
- `activesupport`, `dry-*`, `rexml` → not needed; keep the tree minimal.
- `rubyzip` → deferred to 0.2 (batch packaging needs a real ZIP container; stdlib `zlib` is insufficient).

Development: `rspec`, `webmock`, `vcr`, `rubocop` (+plugins), `simplecov` (>= 1.0, for the branch and method criteria in §9), `simplecov-lcov` (LCOV output for Coveralls — SimpleCov ships HTML and JSON but no LCOV), `yard`, `rake`.

### 4.4 Idioms (enforced by RuboCop where possible)

- `# frozen_string_literal: true` in every file.
- `Data.define` for all immutable value/response objects in `models/` and FA(3) value types.
- `BigDecimal` for every amount; **`Float` is forbidden in any monetary path** (add a spec that greps/asserts this on FA3 model attributes).
- No `RUBY_VERSION` string surgery anywhere; if a version check is ever unavoidable, `Gem::Version.new(RUBY_VERSION)` — but a gem this size should need none.
- UTF-8 throughout; XML serialized with explicit `encoding="UTF-8"`.

### 4.5 Security requirements

- Never log or `inspect`-leak: KSeF tokens, JWTs, symmetric keys, IVs, or full invoice payloads at default log level. Provide a redacting `#inspect` on config/auth objects.
- TLS verification always on; no code path may set `VERIFY_NONE`. Minimum TLS 1.2.
- VCR cassettes must scrub tokens/JWTs/keys via filter hooks; add a spec that scans committed cassettes for `Bearer ` and known secret env values.
- Integration tests read credentials only from env vars (`KSEF_TEST_NIP`, `KSEF_TEST_TOKEN`, `KSEF_ENV=test`); hard-fail if `KSEF_ENV=prod`.

---

## 5. Architecture overview

Two decoupled subsystems in one gem:

1. **Transport** (`Ksef::Client` + friends): auth, crypto, sessions, invoice operations.
2. **FA(3) builder** (`Ksef::FA3`): models, DSL, serializer, parser, validator.

**Decoupling contract:** the transport layer accepts any object responding to `#to_xml` (or a raw XML `String`); the builder works standalone with no HTTP dependency. Neither subsystem `require`s the other's internals.

### 5.1 Directory layout

```
lib/
├── ksef_client.rb            # entry point: requires ksef.rb
├── ksef.rb                   # module Ksef; Zeitwerk loader setup; VERSION
└── ksef/
    ├── client.rb             # the §8 facade (parts under client/)
    ├── configuration.rb      # env, adapter, timeouts, logger, retry policy
    ├── environments.rb       # TEST / DEMO / PROD base URLs (REFERENCE §2)
    ├── errors.rb             # full hierarchy (§6.7)
    ├── http/                 # connection factory (API + credential-free storage), retry,
    │                         # error mapping, X-System-Warning
    ├── auth/                 # the two flows live in client.rb, not in separate *_flow files
    │   ├── challenge.rb
    │   ├── token.rb          # credential object (context NIP + KSeF token)
    │   ├── client.rb         # the six endpoint calls of docs/REFERENCE.md §4.2
    │   ├── token_request.rb, signer.rb, signature_template.rb, xades.rb, validator.rb
    │   ├── schema/           # pinned AuthTokenRequest XSD v2-0 / v2-1
    │   └── access_token.rb   # expiry from validUntil, proactive refresh under a mutex
    ├── crypto/
    │   ├── public_keys.rb    # fetch + cache KSeF certificates, select by usage
    │   ├── encryptor.rb      # session symmetric key gen, payload encryption, RSA-OAEP wrap
    │   └── digest.rb         # SHA-256 hashes + size metadata for payloads
    ├── sessions/
    │   ├── online.rb         # open → send → close
    │   ├── batch.rb          # 0.2
    │   ├── status.rb         # polling with backoff; blocking wait_* helpers
    │   ├── invoice_codes.rb, session_codes.rb        # status tables (REFERENCE §12.1)
    │   └── invoice_state.rb, session_state.rb, upo_page.rb   # response objects
    ├── upo/                  # retrieval, integrity, validation (REFERENCE §12.3, §14.3)
    │   ├── client.rb         # pre-signed link + metered fallback
    │   ├── document.rb       # verbatim bytes; no parsed form on purpose
    │   └── validator.rb, validation.rb
    ├── ksef_number.rb        # the invoice identifier + CRC-8 (docs/REFERENCE.md §13, §13.1)
    ├── invoices/
    │   └── client.rb         # download by KSeF number; query/export in 0.2
    ├── client/               # the §8 facade's parts
    │   ├── receipt.rb        # what send_invoice returns; #reference is the pair
    │   └── session.rb        # the handle client.session { } yields
    ├── models/               # response objects — **not built as a directory**; each
    │                         # subsystem keeps its own, following the auth precedent
    └── fa3/
        ├── invoice.rb, subject.rb, line.rb, address.rb   # models — Phase 1
        ├── correction.rb, corrected_invoice.rb, totals.rb    # KOR (§7.4)
        ├── order.rb, order_line.rb, advance_invoice.rb       # ZAL/ROZ (§7.4)
        ├── formatting.rb     # BigDecimal/date/flag rules, centralised (§7.5)
        ├── nip.rb            # NIP checksum (§7.2)
        ├── vat_rate.rb       # rate code → percentage + summary bucket (§7.3)
        ├── generated/        # FROM XSD CODEGEN — never hand-edited
        ├── builder.rb        # the DSL (§7.2) — done, see §11
        ├── serializer.rb     # Nokogiri; ordering read from generated/, never hand-listed
        ├── parser.rb         # XML → models; retains raw Nokogiri doc — Phase 2
        ├── model_validator.rb, document_validator.rb  # tiers 1a and 1b (§7.7)
        ├── validator.rb      # tier 2 (XSD)
        ├── business_validator.rb  # tier 3 — advisory only (docs/REFERENCE.md §17)
        └── schema/           # pinned FA(3) XSD + upstream MIT licence
```

### 5.2 Thread-safety requirement

A single `Ksef::Client` instance must be safely shareable across threads (Sidekiq is the expected habitat). Config is frozen at construction; per-flow mutable state lives in session/flow objects created per operation; token refresh guarded by a `Mutex`. Add a threaded smoke spec.

### 5.3 Loader note (gem name ≠ namespace)

`require "ksef_client"` loads `lib/ksef_client.rb`, which requires `lib/ksef.rb`; that file configures Zeitwerk manually (`loader.push_dir(__dir__)` with `ksef_client.rb` ignored, inflection `"fa3" => "FA3"`). Document the one-liner in the README ("gem is `ksef_client`, namespace is `Ksef`").

---

## 6. Transport subsystem specification

### 6.1 Configuration & environments

```ruby
Ksef::Client.new(env: :test, auth: ..., logger: nil, timeout: {open: 10, read: 60},
                 retry: Ksef::RetryPolicy.default, adapter: :net_http)
```

`environments.rb` holds the three base URLs (**[VERIFY] resolved:** `docs/REFERENCE.md` §2, each read from that environment's own OpenAPI document) plus a `custom:` escape hatch (base_url override) for future-proofing. `env: :prod` requires no extra ceremony but integration specs must refuse it (§4.5).

### 6.2 HTTP layer

One Faraday connection per client (thread-safe with net_http). Middleware stack: JSON encode/decode, auth header injection (skipped for auth endpoints), instrumentation hook (`config.logger` duck, redacted), error raising mapped through §6.7. Timeouts and proxy honored from config.

### 6.3 Authentication (0.1: **both** KSeF token and certificate/XAdES)

KSeF 2.0 offers exactly two authentication methods (`uwierzytelnianie.md`, verified 2026-08): a qualified electronic signature over an `AuthTokenRequest` XML document, and a KSeF token. Both begin with the same challenge and end at the same token-redemption endpoint.

**Scope change, 2026-08-22.** XAdES was originally deferred to 0.3. It moves into **0.1**, for three reasons:

1. **The token flow cannot be bootstrapped without it.** A KSeF token can only be generated after a one-time XAdES authentication (`tokeny-ksef.md`; `POST /tokens` requires `Bearer`, `/auth/xades-signature` requires nothing). Shipping token-only auth means every new user must first obtain a token using somebody else's client. See `docs/REFERENCE.md` §6a.2.
2. It is what unblocks §12 item 4 — the nightly TEST integration cannot otherwise mint its own credentials. (Done: §12 item 4 resolved 2026-08-23.)
3. `ksef-rb` already ships certificate auth (§1). Token-only is not a viable 0.1.

**Shared prologue.** `POST /auth/challenge` → `{challenge, timestamp, timestampMs, clientIp}`. Challenge lifetime is **10 minutes** *(verified: `uwierzytelnianie.md`)*.

**Token flow:**

1. `GET /security/public-key-certificates` → select the token-encryption certificate by declared usage; cache with TTL.
2. Build plaintext `"#{token}|#{timestampMs}"`, encrypt with RSA-OAEP — SHA-256 with MGF1-SHA-256 (**[VERIFY] resolved:** `docs/REFERENCE.md` §10.1) using OpenSSL `PKey#encrypt` with explicit `rsa_padding_mode: "oaep"`, `rsa_oaep_md`, `rsa_mgf1_md` options.
3. `POST /auth/ksef-token`.

**Certificate / XAdES flow:**

1. Build an `AuthTokenRequest` XML against the pinned auth XSD (`lib/ksef/auth/schema/`, namespace `http://ksef.mf.gov.pl/auth/token/**2.0**` — corrected 2026-08-23; this said 2.1, which `docs/REFERENCE.md` §4.1 and §14.4 established was an inference, and 2.0 is what live TEST accepted per `docs/REFERENCE.md` §6a.4): `Challenge`, `ContextIdentifier`, `SubjectIdentifierType` (`certificateSubject` or `certificateFingerprint`), optional `AuthorizationPolicy` restricting client IPs.
2. Sign it as XAdES via `Ksef::Auth::Signer` — `#sign(xml_string) -> signed_xml_string`. The interface stays, so users with an external signing service or HSM can supply their own; 0.1 additionally ships a built-in enveloped XAdES-BES signer (Nokogiri C14N + OpenSSL) taking a keypair and certificate. Detached form must be rejected with a clear error *(verified: API rejects detached)*.
3. `POST /auth/xades-signature` with `Content-Type: application/xml`.

**Shared epilogue.** Poll the operation, then `POST /auth/token/redeem` → `accessToken` (JWT, short-lived) and `refreshToken` (valid up to **7 days**, reusable) *(verified)*. **Expiry comes from the response's `validUntil`, not from decoding the JWT** — §4.3 excludes the `jwt` dependency and treats the token as opaque, and the contract's `TokenInfo` carries `validUntil` precisely so no decoding is needed. (Corrected 2026-08-23: this said "expiry in `exp`" and "tracks expiry from `exp`", which contradicted §4.3.) `Auth::AccessToken` tracks expiry from `validUntil`, refreshes proactively at ~80% lifetime under mutex; on 401, one refresh-and-replay for **idempotent** requests only.

Note an asymmetry worth honouring: an `accessToken` stays valid until `exp` **even if the user's permissions change**, so revocation is not immediate. Do not treat a live token as proof of current authorisation.

Self-signed certificates are accepted on **TEST only** — never DEMO or PROD.

### 6.4 Crypto module

- Per-session symmetric key: AES-256, random key + IV via `OpenSSL::Cipher` / `SecureRandom`. Mode/padding/IV convention: **[VERIFY] resolved** — AES-256-CBC with PKCS#7, and the IV is a *discrete request field*, not a ciphertext prefix (`docs/REFERENCE.md` §10.1, §14.1).
- Key wrapped with RSA-OAEP using the designated KSeF public certificate — **[VERIFY] resolved:** RSAES-OAEP, SHA-256 + MGF1-SHA-256, selected by `usage` (`docs/REFERENCE.md` §10.1, §10.2).
- `digest.rb` produces the SHA-256 (+ size) metadata the API requires for payloads — **[VERIFY] resolved:** four values per invoice, hash *and* size of both plaintext and ciphertext (`docs/REFERENCE.md` §11.1).
- **Golden vectors:** ~~port at least three encryption test vectors from the official C# client's tests~~ — **superseded 2026-08-23. Those vectors do not exist**: neither reference client commits plaintext/ciphertext pairs. The backstop is instead NIST SP 800-38A and FIPS 180-4 for the primitives, plus behavioural pinning of the two parameters that could silently go wrong. See §11 and `docs/REFERENCE.md` §10.1.

### 6.5 Sessions

**Online (0.1):** open (submits encryption info: wrapped key, IV, cipher metadata) → send N encrypted invoices → close → poll session/invoice status → fetch UPO. Expose both granular calls and a happy-path composite.

**Session-reuse semantics — [VERIFY] resolved 2026-08-23, decided by the human.** The facts came back permissive: a session lives 12 hours, may carry up to 10 000 invoices, and concurrent sessions are allowed (`docs/REFERENCE.md` §11). Neither official client makes the choice for us — **neither offers a composite at all**, so there was no upstream semantics to inherit (`docs/REFERENCE.md` §14.6's investigation notes).

The decision is **a fresh session per `send_invoice`**, with an explicit `client.session { |s| ... }` block when a caller wants one session to carry many invoices. Reasoning: a reused session is mutable state on a client that §5.2 requires to be thread-safe; an opened-but-unused session is cancelled with status `440` so speculative opening is not free; and the API going out of its way to return the *original's* KSeF number on a duplicate (`docs/REFERENCE.md` §12.1) suggests resends are an expected hazard, not one to make likelier by hiding session state. Batching stays available, but as a deliberate act rather than a default. Recorded with the rest of the session-layer decisions at `docs/REFERENCE.md` §11.2a.

**Batch (0.2):** build ZIP of invoices → split into parts → encrypt parts → open batch session → upload parts to returned storage URLs (plain HTTP PUT to object storage — likely bypasses the Faraday auth stack **[VERIFY]**) → close → poll → collect **per-invoice** results *(verified: per-invoice error model)*.

**Status polling:** `status.rb` implements capped exponential backoff (1s, 2s, 4s… max 30s, overall deadline configurable, default 5 min), used by blocking helpers `wait_until_accepted(ref)`; non-blocking single-shot status calls always available.

### 6.6 Invoice operations

0.1: send (via session), status by reference, UPO retrieval, download invoice by KSeF number. 0.2: query/search with filters + pagination, package export. Responses are `Data.define` models carrying: KSeF number, reference numbers, timestamps, acquisition date, raw payloads where useful (UPO XML kept verbatim — it's a signed document users must archive).

### 6.7 Error model

```
Ksef::Error
├── Ksef::ConfigurationError
├── Ksef::AuthenticationError        (challenge/token/JWT problems)
├── Ksef::ValidationError            (raised locally by FA3 validator — §7.7)
├── Ksef::ApiError                   (has #status, #code, #details, #raw)
│   ├── Ksef::InvoiceRejectedError   (schema/business rejection by KSeF)
│   ├── Ksef::SessionError
│   ├── Ksef::RateLimitedError       (retryable; honours Retry-After — REFERENCE §5.5)
│   └── Ksef::ServerError            (5xx; retryable per policy)
└── Ksef::TimeoutError / Ksef::ConnectionError (wrapping Faraday)
```

Map the official error-code catalog into `#code` + human message — **[VERIFY] partially resolved:** the authentication status codes are at `docs/REFERENCE.md` §4.8 and the session/invoice ones at §12.1, both from the pinned contract; the per-endpoint `ExceptionResponse` codes remain open (`docs/REFERENCE.md` §9), collectable from each operation's own `400` description; keep the full catalog table in `docs/errors.md`. **Retry policy:** idempotent GETs and rate-limit/5xx responses retryable with backoff; **invoice submission (POST) is never auto-retried** — surface the error and let the caller decide (duplicate submission is a real-world tax problem).

---

## 7. FA(3) builder subsystem specification

### 7.1 Schema pipeline (codegen)

Dev-only rake task `rake fa3:generate`:

- Input: pinned XSD in `lib/ksef/fa3/schema/`.
- Output: `lib/ksef/fa3/generated/*.rb` — per-complex-type metadata: attribute list, types, min/max occurs, **strict element ordering** (the schema uses sequences; wrong order = rejection), and enum modules (VAT rate codes, currency codes, country codes, invoice type codes…).
- Deterministic, sorted output (clean diffs); every file headed `# GENERATED by rake fa3:generate from FA(3) <version> — DO NOT EDIT`.
- Generated code is **committed**. Regeneration is the designed migration path for future schema revisions (FA(4) → new `Ksef::FA4` namespace alongside, never an in-place rewrite).

Hand-written models/DSL sit **on top of** generated metadata; they consume it (for ordering, enums, presence rules), never duplicate it.

### 7.2 Models & DSL

- English-friendly attribute names; the full English↔Polish mapping (e.g. `issue_date ↔ P_1`, `number ↔ P_2`, `gross_total ↔ P_15`, seller `↔ Podmiot1`, buyer `↔ Podmiot2`, line `↔ FaWiersz`) generated into `docs/field_mapping.md` — accountants and auditors will demand it. Field-name truth comes from the XSD, not from this document.

  **Delivered 2026-08-26.** Deferred since 2026-08-22 behind an explicit trigger — a table covering one invoice type out of seven would read as "not supported" rather than "not documented yet" — and the seventh type landed that day.

  It is **generated**, as this section required: `rake fa3:field_mapping` renders it from a declared mapping in `tasks/field_mapping.rb` plus the pinned XSD, and `rake fa3:verify` fails if the committed file is stale, exactly as it does for `generated/`. Three guards make drift loud: an element path that does not resolve against the schema aborts the run, an attribute that is not a member of its model aborts, and a model member that is neither mapped nor listed with a reason aborts. So the table can fall out of date only by failing to build.

  Descriptions are the Ministry's own `xsd:documentation`, shown only where every occurrence of an element name in the schema agrees — eleven names carry different wording in different places, and guessing which applies would put the wrong statute against a field an auditor is reading.
- Builder DSL as in §8; additionally plain keyword-arg constructors on every model (DSL is sugar, not the only door).
- `Subject` covers NIP + name + address (+ VAT-UE and other identifier variants per schema); include NIP checksum validation (weights 6,5,7,2,3,4,5,6,7; weighted sum mod 11 must equal digit 10 and must not be 10).

### 7.3 Money & VAT computation

- Line: quantity, unit, unit net price, VAT rate code → line net/VAT/gross computed.
- Invoice: per-rate-bucket summaries (`P_13_x`/`P_14_x` — **[VERIFY] resolved:** `docs/REFERENCE.md` §8.1a, read from the XSD's own documentation) and `P_15` computed from lines.
- **Rounding strategy is explicit config** on `build`: `rounding: :per_line` (default) or `:per_summary` — Polish VAT law permits both; silently choosing one creates 1-grosz mismatches with users' ERPs. Both strategies round half-up to 2 dp at the documented point.
- Every computed value is **overridable** (ERP-as-source-of-truth users); when overridden, tier-3 validation (§7.7) still checks reconciliation and reports. **No `strict: false` escape exists or is needed** — an earlier draft promised one, but tier 3 shipped as advisory (`Invoice#warnings`), so there is nothing to escape from. Corrected 2026-08-26.

### 7.4 Invoice types

Seven types share a common core: `VAT`, `KOR`, `ZAL`, `ROZ`, `UPR`, `KOR_ZAL`, `KOR_ROZ`. Model as core + per-type required/forbidden-field rule sets (driven by generated metadata where the XSD encodes it; by hand-written rules where it's business guidance). **Implementation order: VAT → KOR → ZAL/ROZ → UPR → KOR_ combinations.** Corrections (KOR) get the largest test budget: references to corrected invoices and before/after row conventions are where complexity concentrates. Schema-complete support includes the FA(3) attachment node (`Zalacznik`) at build/parse level; *operational* attachment submission constraints are out of scope for 0.1 (document this).

### 7.5 Serializer

Nokogiri-based; consumes generated ordering; formatting rules centralized: BigDecimal → schema-conformant decimal strings (no scientific notation, correct scale), dates ISO-8601, correct root namespace + `KodFormularza`/`WariantFormularza` header (**[VERIFY] resolved:** `docs/REFERENCE.md` §8 — the element is `FA`, `FA (3)` is the `kodSystemowy`, note the space), UTF-8 declaration. Property: serializer output for every fixture validates against the pinned XSD.

### 7.6 Parser

`Ksef::FA3.parse(xml)` → model objects, best-effort typed; **always** retains the raw `Nokogiri::XML::Document` (`#raw_document`) so nothing unmapped is lost. Ministry-published FA(3) sample files are the fixture corpus. **Round-trip law:** for every builder golden file, `parse(serialize(invoice))` reproduces equivalent models, and `serialize(parse(sample))` is XSD-valid.

**Corrected 2026-08-24 — the corpus is not where this said it was.** `ksef-api` publishes no example invoice at all; the samples live in `CIRFMF/ksef-pdf-generator` and `CIRFMF/ksef-client-csharp`, pinned per-repository at `spec/fixtures/fa3/` (`docs/REFERENCE.md` §1.4). Two consequences for the law above. The C# samples are **templates** carrying `#nip#`-style placeholders, so a fixture helper substitutes them; and `#raw_document` is load-bearing rather than a nicety, because a real sample uses `Podmiot3`, `DaneKontaktowe`, `OkresFa` and much else this model does not carry — so `serialize(parse(sample))` is XSD-valid *and lossy*, and the law says nothing stronger than validity on purpose. `#unmapped_elements` exists so that loss is visible before a caller re-serialises a document they did not write.

### 7.7 Validation — three tiers, one entry point

`invoice.validate!` (and `#valid?` / `#errors`) runs:

1. **Model tier (Ruby):** required fields per invoice type, enum membership, NIP checksums, date sanity — fast, readable, field-addressed errors.
2. **Schema tier (XSD):** Nokogiri validation against the pinned XSD — **[VERIFY] resolved** — MIT, so the schemas are bundled (`docs/REFERENCE.md` §1.2); if redistribution is disallowed, ship a first-run fetch-and-cache with pinned checksum instead of bundling.
3. **Business tier:** reconciliation rules that pass XSD but bounce at KSeF — line sums vs rate summaries vs `P_15`, rate-bucket consistency, correction references present for KOR types. Seed from Ministry guidance **[VERIFY published business-rule list]**; the catalog grows over the gem's life.

Transport's `send_invoice` runs `validate!` by default (`validate: false` opt-out).

**Amended 2026-08-24 — tier 1 is two things, not one.** `docs/REFERENCE.md` §15.1 pins the
admission rules KSeF actually applies, and four of the six are **byte-level properties of the
serialized document**: no BOM, no processing instructions, a prolog that does not contradict
UTF-8, and no discouraged Unicode characters. A model tier as described above — "required
fields per invoice type, enum membership, NIP checksums, date sanity" — structurally cannot
see any of them, because at that point there is no document yet. So tier 1 splits:

1. **Model checks**, as originally described, on the object graph.
2. **Document checks**, on the bytes `#to_xml` produces, run before they are hashed and
   encrypted.

Both belong under `validate!`, and (2) has to run last. Note tier 2 now also covers
well-formedness, which the XSD does not: libxml2 recovers from broken XML by default, and
`Validator` had to be taught to consult `document.errors` (§15.1).

**Built 2026-08-24.** `Ksef::FA3::ModelValidator` is (1) and `Ksef::FA3::DocumentValidator` is
(2); `Invoice#errors` runs model → document → schema and returns `Issue` values carrying a
field path, so a caller learns *which* value to fix. Two properties worth keeping:

- **The model tier short-circuits.** Serialisation raises on a bad NIP, a nameless seller or a
  rate code with no summary bucket, so attempting it after a model failure would replace a list
  of addressed errors with one exception about whichever came first. (It also raised on a line
  with no derivable net until 2026-08-26, when that row became legal — see §7.4.) Its aim is therefore the
  stronger statement — *what the model tier passes, `#to_xml` can serialise* — and it is an
  **aim, not a proof**. A review on 2026-08-24 falsified the absolute twice, through
  `annotations` and the buyer's yes/no flags, both public constructor fields the tier did not
  inspect; both are now checked. Treat a new counterexample as a gap to close here, not as a
  surprise.
- **`#errors` reports rather than raises**, including for a serialisation refusal the model
  tier did not anticipate, and for text that is tagged UTF-8 but is not — the case §15.1 calls
  the likeliest real-world rejection, and the one that used to make it throw
  `Encoding::CompatibilityError` from `String#strip`. Stated as behaviour rather than as a
  guarantee: it is bounded by the input classes that have been tried.

**Tier 3 built 2026-08-26**, and redesigned the same day after a five-lens audit — `Ksef::FA3::BusinessValidator`, reached through **`Invoice#warnings`** rather than `#errors`. That is the substantive amendment to this section: §7.7 above assumed tier 3 would join `validate!`, and it must not.

It holds one rule, `Σ P_13_* + Σ P_14_* ≈ P_15`, compared over **figures the document states** and never against the model's own derivation. Its grounding is **empirical** (`docs/REFERENCE.md` §15.6 grounding 3), not definitional: `P_15`'s annotation says nothing about the buckets, and the definitional alternative — check `P_13_1` against the rows — is falsified by ten of the fourteen modelled stated-summary samples, because a correction's buckets are deltas and an advance's are pre-payments.

**Why it cannot be an error.** A Polish invoice whose nets are computed back *w stu* from round gross prices misses the rule by roughly a grosz per line, and is entirely legal — the Ministry's own Przykład 1 is one. An error would refuse such invoices through `Client#send_invoice`, which is precisely the mistake that got KSeF's own proposed business rule withdrawn. §14.3 is the precedent for reporting rather than refusing.

The one-grosz tolerance is what the single corpus witness shows and no more; it is not a bound, because the error scales with line count and with the issuer's rounding convention. `docs/REFERENCE.md` §17 records all of it, including the two false positives the first version produced and the `P_15`-was-derived defect (§17.2) that grounding the rule uncovered.

The catalogue grows as evidence arrives — §17.4 lists what would ground the next rule, starting with `Rozliczenie/DoZaplaty`, the one arithmetic identity the XSD actually states. **Do not synthesise rules from Polish VAT law and record them as verified facts** (§15.6).

---

## 8. Public API contract (must run verbatim by 0.1.0)

```ruby
client = Ksef::Client.new(
  env:  :test,
  auth: Ksef::Auth::Token.new(context_nip: "9999999999", token: ENV["KSEF_TOKEN"])
)

invoice = Ksef::FA3.build do |f|
  f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
  f.buyer  nip: "1111111111", name: "Klient S.A.",     address: { street: "Długa 2",  city: "Kraków",   postal_code: "30-001", country: "PL" }
  f.number "FV/2026/08/001"
  f.issue_date Date.today
  f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23"
end

result = client.send_invoice(invoice)          # validate! → encrypt → session → submit
status = client.wait_until_accepted(result.reference)
status.ksef_number                              # => "9999999999-2026…"
upo = client.upo(result.reference)              # signed UPO XML, keep verbatim
```

The README quickstart is this snippet plus install instructions — a developer goes from `gem install` to a submitted TEST invoice in ~20 lines.

---

## 9. Testing strategy

| Tier | Tooling | Scope | When |
|---|---|---|---|
| Unit | RSpec + WebMock | request shaping, crypto primitives, models, serializer, validator | every push, full matrix |
| Recorded | VCR (scrubbed per §4.5) | full auth + session flows against recorded TEST responses | **planned, not yet built** — no cassette exists as of 2026-08-23; WebMock stubs cover this ground for now |
| Golden files | RSpec fixtures | builder XML per invoice type vs approved snapshots; XSD-valid; round-trip law (§7.6); crypto vectors — NIST/FIPS, not C#, see §6.4 | every push |
| Live integration | RSpec, env-gated (`KSEF_ENV=test` + creds) | end-to-end §8 contract, incl. TEST env test-data helper API for provisioning. Three specs exist — auth, crypto, session — and **all three have run green against TEST** (auth 2026-08-23, the other two 2026-08-24) | **nightly** CI + pre-release, never per-PR |

**Coverage gate (ratcheted 2026-08-22, then 95 → 96 → 97 on 2026-08-24, then 97 → 98 at the Phase 2 boundary on 2026-08-26):** three criteria, all enforced by SimpleCov and all excluding `generated/` — **line 99, branch 98, method 100**. The `minimum_coverage` call in `spec/spec_helper.rb` is the gate that fails the build and is therefore the authority; every restatement, here included, is a copy that has gone stale before.

**There is a second gate, and it is stricter than the floors.** Coveralls posts a `coverage/coveralls` commit status that blocks the PR on any *decline* against the base branch, measured as a combined line+branch figure. It is not a floor and does not ratchet: one new uncovered branch is enough. The workflow's `fail-on-error` was `false` on the reasoning that Coveralls is reporting rather than enforcement — but that flag governs only the action erroring, never the status, so the policy was stated and not applied; it is `true` as of 2026-08-26. In practice this is the gate that catches a conditional added without a test per path, which the percentage floors are too slack to see.

Originally this said "90% lines". That turned out to be a weak gate: the suite sat at 99% line coverage while branch coverage was 83%, i.e. seventeen conditional paths were untested behind fully-covered lines. Branch coverage is the one that finds real gaps; line coverage mostly confirms files are loaded.

Floors sit just under the achieved numbers so they ratchet. Raise them as the real figures move up; do not lower one to make a change pass. Branch is 98 rather than 100 because ten guards — seven `&.` and three plain `if`/`return` — defend against states that cannot occur, and contorting tests to reach them proves nothing. **That justification covers exactly those ten**: an eleventh appeared with the last three invoice types, defending a state that *can* occur, and it was a missing test rather than an unreachable guard. The distinction is the whole point of the margin, so a rise in the count is worth investigating rather than absorbing. Deliberate margin, not a knife edge at the actuals: a floor pinned to the exact current figure fails on refactors that change nothing about test quality. Because these are percentages, the absolute number of untested branches they permit grows with the codebase — **re-ratchet at each phase boundary**, not once. Requires SimpleCov >= 1.0, where the supported criteria are `[:line, :branch, :method, :oneshot_line]`; 0.x supports only line and branch.

A filtered run — one file, one example, or a tag selector — legitimately exercises less of the library, so the gate applies to full runs only. Otherwise the nightly `--tag integration` job would fail on coverage rather than on tests.

A threaded smoke spec for §5.2. A spec asserting no committed cassette contains unscrubbed secrets.

---

## 10. Repository, CI, and release engineering

- **CI (GitHub Actions):** `test.yml` — matrix `["3.2","3.3","3.4","4.0","head"]` (head: `continue-on-error`), RuboCop job, coverage artifact. `nightly.yml` — live TEST-env integration on schedule, creds from **environment** secrets on `ksef-test` (`docs/REFERENCE.md` §6a.3 — a repository secret is readable by every workflow in the repo). `release.yml` — tag-triggered, **RubyGems Trusted Publishing (OIDC)** — no long-lived API keys anywhere.
- **Docs:** README (quickstart = §8, support policy, gem-vs-namespace note, JRuby/MRI statement), `docs/field_mapping.md` (generated), `docs/errors.md`, `docs/REFERENCE.md` (verification ledger), CHANGELOG (keep-a-changelog), CONTRIBUTING, SECURITY.md.
- **Changelog compatibility header:** every release entry states the KSeF API version and FA schema revision it targets — the Ministry ships changes continuously; users must be able to answer "which gem version for which API state".
- **Versioning:** SemVer. EOL-ruby drops in minors (documented) — but see the §3 note: the 3.2 floor is a standing exception and is not dropped on EOL. FA(4), when it comes: additive `Ksef::FA4` namespace, `Ksef::FA3` maintained per deprecation policy — never a breaking in-place rewrite.
- **Pre-release ritual:** green nightly on the release commit **and** one local full-suite run on Ruby 3.2 (the floor contract deserves a deliberate look).

---

## 11. Milestones and acceptance criteria

### Phase 1 — Foundations (two parallel tracks)
Transport: repo scaffold, gemspec, CI matrix green on empty suite, `configuration`/`environments`/`http`/`errors` with unit tests. Builder: XSD + OpenAPI pinned and ledgered in `docs/REFERENCE.md`, codegen task producing committed `generated/`, core models + serializer, golden files for plain VAT invoices validating against XSD.
**Done when:** codegen is reproducible (`rake fa3:generate` → empty diff), VAT golden files XSD-valid, CI matrix green.

**✅ Complete 2026-08-22.** All three gates pass. Two things landed beyond the stated scope because they turned out to be prerequisites: offline XSD validation (the schema cannot be compiled as shipped — see `docs/REFERENCE.md` §8.3) and the auth schema pinning. Two things in §7.2's scope did not: the `Ksef::FA3.build` DSL, and `docs/field_mapping.md`. Both are required before 0.1.0 and are tracked in Phase 2.

### Phase 2 — Make it real
Transport: **both auth flows** — KSeF token *and* certificate/XAdES (§6.3) — crypto module **with golden vectors passing**, online session end-to-end against TEST (recorded + live), send/status/UPO/download. Builder: **the `Ksef::FA3.build` DSL (§8)**, validator tiers 1–3, computed summaries with both rounding strategies, remaining invoice types (order per §7.4), parser + round-trip law green on Ministry samples.

The DSL is listed explicitly because it was previously implied only by the "Done when" gate below — §8's snippet opens with `Ksef::FA3.build`, so the gate could not pass without it, but no scope list named it. Build it **first** in this phase: it is small now that the models exist, its shape is fixed by §8, and until it exists the README's headline example is aspirational.

Build the **certificate flow first**: it is the only one that can bootstrap a credential from nothing, so it is what makes the nightly TEST suite self-sufficient and unblocks §12 item 4. (Both done as of 2026-08-23.) The token flow then has something to authenticate with when minting its first token.

**Done when:** §8 contract runs against TEST; a KSeF token can be minted end-to-end by this gem with no external client; all seven types build, validate, round-trip.

**In progress, 2026-08-23.** The DSL is done — §8's snippet runs verbatim and validates. **The certificate flow is complete and verified against live TEST**: request document, XAdES-BES signer, and the four `docs/REFERENCE.md` §4.2 endpoints the bootstrap exercises — challenge, `xades-signature`, `GET /auth/{ref}` and `redeem`. **`refresh` and `ksef-token` are implemented but have never run live** (corrected 2026-08-23: this claimed all six calls were live-verified, which the bootstrap's call list does not support). A KSeF token has been minted end to end by this gem with no external client, which satisfies the second "Done when" gate and resolves §12 item 4.

**Both auth flows and the crypto module have since landed** (`Ksef::Crypto`, `Ksef::Auth::Token`, `POST /auth/ksef-token`). One correction to §6.4 while doing it: the golden vectors it asks for **do not exist upstream** — neither reference client commits plaintext/ciphertext pairs — so the primitives are pinned to NIST SP 800-38A and FIPS 180-4 instead, and the OAEP digest and MGF1 digest are pinned behaviourally rather than by trusting an option name. `docs/REFERENCE.md` §10.1 records what replaced them and why it is at least as strong.

**The session layer, UPO handling and the `Ksef::Client` facade have landed too**, so §8's snippet runs end to end — `spec/ksef/client_spec.rb` drives it verbatim against stubs, and `spec/integration/session_flow_spec.rb` drives it against the real service.

**The first gate is met, as of 2026-08-24.** **Verified against live TEST on 2026-08-24** (nightly run `32692339217`): a session was opened, an invoice this gem built was encrypted, submitted and **accepted**, a KSeF number was assigned and its CRC-8 agreed with ours, the session reported processed after close, and the UPO came back in the `upo-v4-3` namespace with its bytes matching `x-ms-meta-hash`. Twenty-two of that run's twenty-four examples passed. It also answered `docs/REFERENCE.md` §9's last session-layer question — the collective `downloadUrl` arrives **absolute** — and turned §14.6's `X-KSeF-Feature` header from believed into verified.

The two failures were **ours, not the service's**, and both are now fixed. One spec asserted `be_success` on a deliberately duplicated invoice, which is a contradiction: KSeF did exactly what §12.1 describes, returning `440` with the original's `originalKsefNumber`. The other found a real defect — a genuine UPO is XAdES-signed and therefore fails upstream's own UPO schema, which declares no `ds:Signature`; none of the six published examples is signed, so nothing offline could have shown it (§14.7).

Gate status, precisely:

| Gate | State |
|---|---|
| §8 contract runs against TEST | **met**, verified live 2026-08-24 (nightly run `32692339217`) |
| A KSeF token minted end-to-end with no external client | **met**, verified live 2026-08-23 (§6a.4) |
| All seven types build, validate, round-trip | **met**, 2026-08-26 — all seven, round-trip and **validator tier 1** included. Twenty-two of the twenty-six Ministry samples go through end to end; the other four are refused for a *construct* (gross pricing, non-NIP buyer), not a type. Tier 3 landed the same day, advisory (§7.7) |

**Phase 2's three gates are met and its build scope is done, as of 2026-08-26.** Validator tier 3 landed that day (§7.7, advisory) and `docs/field_mapping.md` with it (§7.2, generated).

**One scope-list item remains, and it is not a gate: there is no VCR cassette.** The scope above
asks for the session flow "recorded + live", and §9's own testing table says the recorded half is
"planned, not yet built".

**Two further gaps exist and belong to Phase 3, not here** — recorded because they were twice
mis-assigned to Phase 2 before this was checked against the scope list word by word:

- **`Zalacznik` is not carried.** §7.4 asks for the attachment node "at build/parse level" and
  puts only *operational* submission constraints out of 0.1 scope, so build/parse support is a
  0.1.0 requirement. Phase 2 cites §7.4 for the **implementation order of invoice types** and
  nothing else, so this was never Phase 2's. Two Ministry samples carry one.
- **`download` and `refresh` have never run against TEST.** Neither is a stated requirement of
  any phase: the scope above lists `download` as a *feature* and it is implemented, `refresh`
  is not named at all, and Phase 3's bar is "nightly integration green ≥ 3 consecutive nights",
  which the current nightly meets without exercising either. So this is a judgement about
  confidence, not an unmet commitment — worth closing before 0.1.0, and worth not dressing up
  as scope.

The lesson, since it has now recurred three times in one day: **read the scope list before
saying what is left.** "Complete" was wrong, "two items" was wrong, and both were assertions
about a sentence nobody had re-read.

The sentence here read "validator tier 3, and only that" until 2026-08-26, and that was an inconsistency introduced in the same commit that created the other half of it: §7.2's deferral of the field mapping carried an explicit trigger — *"it lands once the models cover all seven types"* — and Phase 1's note above records it as "required before 0.1.0 and tracked in Phase 2". The seventh type landed that day, so the trigger fired and the deferral ended.

**The parser landed 2026-08-24**, with the sample corpus §7.6 assumed and did not have
(`docs/REFERENCE.md` §1.4). Two findings changed the plan around it, both ledgered:

- **Tier 3's rule catalogue does not exist upstream.** `faktury/weryfikacja-faktury.md` — the
  document `docs/REFERENCE.md` §9 named as the place to look — is a list of *technical admission* checks, and
  turned out to be the missing first-tier source for tier **1** instead. No file in
  `ksef-api` states a reconciliation rule (`docs/REFERENCE.md` §15.6). So tier 1 is now the
  better-specified of the two and should be built first — which reverses **`docs/REFERENCE.md` §9's** framing of
  tier 3 as "the only genuinely open blocker", i.e. the thing to resolve first. (An earlier
  version of this note said it reversed §7.7's order; §7.7 states the order the tiers *run*
  in, which is unchanged. See §7.7's amendment for what did change there.)
- **Tier 1 is provably not redundant with tier 2.** Upstream ships an invoice that is
  XSD-valid — once its `#nip#` placeholder is substituted (§1.4) — and that the pinned rules
  say KSeF rejects, on forbidden C1 characters a schema cannot see (§15.1). It is pinned, and
  `spec/ksef/fa3/round_trip_spec.rb` asserts both halves.

### Phase 3 — Publish 0.1.0
Docs complete, nightly integration green ≥ 3 consecutive nights, trusted-publishing pipeline verified with an `-rc` release, then `0.1.0` tagged and published.
**Done when:** `gem install ksef_client` + README quickstart works for a clean user against TEST.

### 0.2
Batch sessions (ZIP/parts/storage upload, per-invoice results; adds `rubyzip`), invoice query/search + pagination, package export, complete error-code catalog + retry semantics hardened.

### 0.3
KSeF certificate lifecycle endpoints (`/certificates/*` — enrolling and managing KSeF-issued certificates, distinct from the qualified signature used to authenticate), permissions API, QR code generation for offline modes.

*(XAdES auth moved out of 0.3 and into 0.1 on 2026-08-22 — see §6.3.)*

### 1.0
After sustained production use; API stability promise begins.

---

## 12. Open questions (flag to the human, don't self-decide)

1. ~~Repo/org placement and gem author metadata (name, email, homepage).~~ **Resolved:** Tibor Molnár, `tibor@timcraft.pl`, `github.com/tibortc/ksef_client`; asserted by `spec/release_readiness_spec.rb`.
2. ~~XSD redistribution outcome (§7.7 tier 2) — bundle vs fetch-and-cache.~~ **Resolved:** the schemas are MIT-licensed, so they are bundled and no fetch-and-cache fallback is needed (`docs/REFERENCE.md` §1.2, which also gives the test for where a *third-party* schema may live).
3. Default rounding strategy confirmation (`:per_line` proposed) once real accounting examples are in fixtures — **which has now happened**: the Ministry's 26
worked examples are pinned at `spec/fixtures/fa3/mf-samples/` (docs/REFERENCE.md §1.5), so this
decision is ready to be taken.
4. ~~Whether TEST-env credentials for nightly CI come from a dedicated test NIP (recommended) — needs human to provision via the TEST self-service tools.~~ **Resolved 2026-08-23.** A dedicated invented NIP, provisioned by `rake auth:bootstrap` (docs/REFERENCE.md §6a.3) rather than by hand. `KSEF_TEST_NIP` and `KSEF_TEST_TOKEN` are stored in the `ksef-test` environment and the nightly schedule is enabled. The run also confirmed that KSeF accepts this gem's XAdES signature (`docs/REFERENCE.md` §6a.4).
5. ~~Any trademark/naming sensitivities around "KSeF" in the gem description (likely none — official SDKs use it — but confirm before publishing).~~ **Resolved 2026-08-23 — confirmed by the human**, on the basis the question anticipated. Two KSeF-named gems are already published unchallenged — [`ksef`](https://rubygems.org/gems/ksef) and [`ksef-rb`](https://rubygems.org/gems/ksef-rb), both catalogued in §1 — and the Ministry's own C# and Java SDKs use the name. Settled practice, not a trademark search, which is enough to publish on: `0.1.0.rc1` did so on 2026-08-22.
