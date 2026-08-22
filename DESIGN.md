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
5. Prohibitions summary (details throughout): no dependency additions beyond §4.3 without flagging; no upper bound on `required_ruby_version`; no secrets in logs or VCR cassettes; no auto-retry of non-idempotent requests; no hand edits to `lib/ksef/fa3/generated/`; never point tests at the PROD environment.

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
    ├── client.rb             # facade
    ├── configuration.rb      # env, adapter, timeouts, logger, retry policy
    ├── environments.rb       # TEST / DEMO / PROD base URLs [VERIFY values]
    ├── errors.rb             # full hierarchy (§6.7)
    ├── http/                 # Faraday connection factory, middleware, instrumentation
    ├── auth/
    │   ├── challenge.rb
    │   ├── token.rb          # credential object (context NIP + KSeF token)
    │   ├── token_flow.rb     # challenge → RSA-OAEP → JWT
    │   ├── xades_flow.rb     # 0.1; AuthTokenRequest → sign → submit → redeem
    │   ├── signer.rb         # pluggable signer interface + built-in XAdES-BES signer
    │   ├── schema/           # pinned AuthTokenRequest XSD v2-0 / v2-1
    │   └── access_token.rb   # JWT storage, expiry, refresh
    ├── crypto/
    │   ├── public_keys.rb    # fetch + cache KSeF certificates, select by usage
    │   ├── encryptor.rb      # session symmetric key gen, payload encryption, RSA-OAEP wrap
    │   └── digest.rb         # SHA-256 hashes + size metadata for payloads
    ├── sessions/
    │   ├── online.rb         # open → send → close → status lifecycle
    │   ├── batch.rb          # 0.2
    │   └── status.rb         # polling with backoff; blocking wait_until_* helpers
    ├── invoices/             # send, status, upo, download; query/export in 0.2
    ├── models/               # Data.define response objects (SessionRef, SendResult, Upo, …)
    └── fa3/
        ├── invoice.rb, subject.rb, line.rb, address.rb   # models — Phase 1
        ├── annotations.rb, payment.rb, correction.rb     # models — Phase 2
        ├── formatting.rb     # BigDecimal/date/flag rules, centralised (§7.5)
        ├── nip.rb            # NIP checksum (§7.2)
        ├── vat_rate.rb       # rate code → percentage + summary bucket (§7.3)
        ├── generated/        # FROM XSD CODEGEN — never hand-edited
        ├── builder.rb        # the DSL (§7.2) — NOT YET WRITTEN, required for 0.1.0
        ├── serializer.rb     # Nokogiri; ordering read from generated/, never hand-listed
        ├── parser.rb         # XML → models; retains raw Nokogiri doc — Phase 2
        ├── validator.rb      # three tiers (§7.7); tier 2 (XSD) done, tiers 1 and 3 Phase 2
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

`environments.rb` holds the three base URLs **[VERIFY]** plus a `custom:` escape hatch (base_url override) for future-proofing. `env: :prod` requires no extra ceremony but integration specs must refuse it (§4.5).

### 6.2 HTTP layer

One Faraday connection per client (thread-safe with net_http). Middleware stack: JSON encode/decode, auth header injection (skipped for auth endpoints), instrumentation hook (`config.logger` duck, redacted), error raising mapped through §6.7. Timeouts and proxy honored from config.

### 6.3 Authentication (0.1: **both** KSeF token and certificate/XAdES)

KSeF 2.0 offers exactly two authentication methods (`uwierzytelnianie.md`, verified 2026-08): a qualified electronic signature over an `AuthTokenRequest` XML document, and a KSeF token. Both begin with the same challenge and end at the same token-redemption endpoint.

**Scope change, 2026-08-22.** XAdES was originally deferred to 0.3. It moves into **0.1**, for three reasons:

1. **The token flow cannot be bootstrapped without it.** A KSeF token can only be generated after a one-time XAdES authentication (`tokeny-ksef.md`; `POST /tokens` requires `Bearer`, `/auth/xades-signature` requires nothing). Shipping token-only auth means every new user must first obtain a token using somebody else's client. See `docs/REFERENCE.md` §6a.2.
2. It is what unblocks §12.4 — the nightly TEST integration cannot otherwise mint its own credentials. (Done: §12.4 resolved 2026-08-23.)
3. `ksef-rb` already ships certificate auth (§1). Token-only is not a viable 0.1.

**Shared prologue.** `POST /auth/challenge` → `{challenge, timestamp, timestampMs, clientIp}`. Challenge lifetime is **10 minutes** *(verified: `uwierzytelnianie.md`)*.

**Token flow:**

1. `GET /security/public-key-certificates` → select the token-encryption certificate by declared usage; cache with TTL.
2. Build plaintext `"#{token}|#{timestampMs}"`, encrypt with RSA-OAEP (digest/MGF per docs **[VERIFY]**) using OpenSSL `PKey#encrypt` with explicit `rsa_padding_mode: "oaep"`, `rsa_oaep_md`, `rsa_mgf1_md` options.
3. `POST /auth/ksef-token`.

**Certificate / XAdES flow:**

1. Build an `AuthTokenRequest` XML against the pinned auth XSD (`lib/ksef/auth/schema/`, namespace `http://ksef.mf.gov.pl/auth/token/2.1`): `Challenge`, `ContextIdentifier`, `SubjectIdentifierType` (`certificateSubject` or `certificateFingerprint`), optional `AuthorizationPolicy` restricting client IPs.
2. Sign it as XAdES via `Ksef::Auth::Signer` — `#sign(xml_string) -> signed_xml_string`. The interface stays, so users with an external signing service or HSM can supply their own; 0.1 additionally ships a built-in enveloped XAdES-BES signer (Nokogiri C14N + OpenSSL) taking a keypair and certificate. Detached form must be rejected with a clear error *(verified: API rejects detached)*.
3. `POST /auth/xades-signature` with `Content-Type: application/xml`.

**Shared epilogue.** Poll the operation, then `POST /auth/token/redeem` → `accessToken` (JWT, short-lived, expiry in `exp`) and `refreshToken` (valid up to **7 days**, reusable) *(verified)*. `Auth::AccessToken` tracks expiry from `exp`, refreshes proactively at ~80% lifetime under mutex; on 401, one refresh-and-replay for **idempotent** requests only.

Note an asymmetry worth honouring: an `accessToken` stays valid until `exp` **even if the user's permissions change**, so revocation is not immediate. Do not treat a live token as proof of current authorisation.

Self-signed certificates are accepted on **TEST only** — never DEMO or PROD.

### 6.4 Crypto module

- Per-session symmetric key: AES-256, random key + IV via `OpenSSL::Cipher` / `SecureRandom`. Mode/padding/IV convention **[VERIFY]** (expected CBC + PKCS#7 with documented IV placement).
- Key wrapped with RSA-OAEP using the designated KSeF public certificate **[VERIFY parameters]**.
- `digest.rb` produces the SHA-256 (+ size) metadata the API requires for payloads **[VERIFY exact fields/encoding]**.
- **Golden vectors:** port at least three encryption test vectors from the official C# client's tests (or generate with it) and assert byte-for-byte equality of our primitives. This is the anti-hallucination backstop for the whole module.

### 6.5 Sessions

**Online (0.1):** open (submits encryption info: wrapped key, IV, cipher metadata) → send N encrypted invoices → close → poll session/invoice status → fetch UPO. Expose both granular calls and a happy-path composite (`client.send_invoice(invoice)` opens/uses a session appropriately — exact session-reuse semantics per docs **[VERIFY]**, e.g. whether one session may carry multiple invoices and for how long).

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
│   ├── Ksef::RateLimitedError       (retryable; honors Retry-After [VERIFY])
│   └── Ksef::ServerError            (5xx; retryable per policy)
└── Ksef::TimeoutError / Ksef::ConnectionError (wrapping Faraday)
```

Map the official error-code catalog **[VERIFY from OpenAPI/docs]** into `#code` + human message; keep the full catalog table in `docs/errors.md`. **Retry policy:** idempotent GETs and rate-limit/5xx responses retryable with backoff; **invoice submission (POST) is never auto-retried** — surface the error and let the caller decide (duplicate submission is a real-world tax problem).

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

  **Deferred as of 2026-08-22.** `docs/field_mapping.md` is not written yet. Generating it from the current model set would produce a table covering one invoice type out of seven, which for an audience checking whether *their* field is supported is worse than no table — an absent row would read as "not supported" rather than "not documented yet". It lands once the models cover all seven types (§7.4). At that point it must be generated from a declared mapping rather than hand-written, or it will drift.
- Builder DSL as in §8; additionally plain keyword-arg constructors on every model (DSL is sugar, not the only door).
- `Subject` covers NIP + name + address (+ VAT-UE and other identifier variants per schema); include NIP checksum validation (weights 6,5,7,2,3,4,5,6,7; weighted sum mod 11 must equal digit 10 and must not be 10).

### 7.3 Money & VAT computation

- Line: quantity, unit, unit net price, VAT rate code → line net/VAT/gross computed.
- Invoice: per-rate-bucket summaries (`P_13_x`/`P_14_x` **[VERIFY bucket↔rate mapping from schema]**) and `P_15` computed from lines.
- **Rounding strategy is explicit config** on `build`: `rounding: :per_line` (default) or `:per_summary` — Polish VAT law permits both; silently choosing one creates 1-grosz mismatches with users' ERPs. Both strategies round half-up to 2 dp at the documented point.
- Every computed value is **overridable** (ERP-as-source-of-truth users); when overridden, tier-3 validation (§7.7) still checks reconciliation and reports — with a documented `strict: false` escape.

### 7.4 Invoice types

Seven types share a common core: `VAT`, `KOR`, `ZAL`, `ROZ`, `UPR`, `KOR_ZAL`, `KOR_ROZ`. Model as core + per-type required/forbidden-field rule sets (driven by generated metadata where the XSD encodes it; by hand-written rules where it's business guidance). **Implementation order: VAT → KOR → ZAL/ROZ → UPR → KOR_ combinations.** Corrections (KOR) get the largest test budget: references to corrected invoices and before/after row conventions are where complexity concentrates. Schema-complete support includes the FA(3) attachment node (`Zalacznik`) at build/parse level; *operational* attachment submission constraints are out of scope for 0.1 (document this).

### 7.5 Serializer

Nokogiri-based; consumes generated ordering; formatting rules centralized: BigDecimal → schema-conformant decimal strings (no scientific notation, correct scale), dates ISO-8601, correct root namespace + `KodFormularza`/`WariantFormularza` header **[VERIFY values]**, UTF-8 declaration. Property: serializer output for every fixture validates against the pinned XSD.

### 7.6 Parser

`Ksef::FA3.parse(xml)` → model objects, best-effort typed; **always** retains the raw `Nokogiri::XML::Document` (`#raw_document`) so nothing unmapped is lost. Ministry-published FA(3) sample files are the fixture corpus. **Round-trip law:** for every builder golden file, `parse(serialize(invoice))` reproduces equivalent models, and `serialize(parse(sample))` is XSD-valid.

### 7.7 Validation — three tiers, one entry point

`invoice.validate!` (and `#valid?` / `#errors`) runs:

1. **Model tier (Ruby):** required fields per invoice type, enum membership, NIP checksums, date sanity — fast, readable, field-addressed errors.
2. **Schema tier (XSD):** Nokogiri validation against the pinned XSD — confirm the XSD's redistribution terms **[VERIFY]**; if redistribution is disallowed, ship a first-run fetch-and-cache with pinned checksum instead of bundling.
3. **Business tier:** reconciliation rules that pass XSD but bounce at KSeF — line sums vs rate summaries vs `P_15`, rate-bucket consistency, correction references present for KOR types. Seed from Ministry guidance **[VERIFY published business-rule list]**; the catalog grows over the gem's life.

Transport's `send_invoice` runs `validate!` by default (`validate: false` opt-out).

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
| Recorded | VCR (scrubbed per §4.5) | full auth + session flows against recorded TEST responses | every push |
| Golden files | RSpec fixtures | builder XML per invoice type vs approved snapshots; XSD-valid; round-trip law (§7.6); crypto vectors vs official C# client (§6.4) | every push |
| Live integration | RSpec, env-gated (`KSEF_ENV=test` + creds) | end-to-end §8 contract, incl. TEST env test-data helper API for provisioning | **nightly** CI + pre-release, never per-PR |

**Coverage gate (ratcheted 2026-08-22):** three criteria, all enforced by SimpleCov and all excluding `generated/` — **line 99, branch 95, method 100**.

Originally this said "90% lines". That turned out to be a weak gate: the suite sat at 99% line coverage while branch coverage was 83%, i.e. seventeen conditional paths were untested behind fully-covered lines. Branch coverage is the one that finds real gaps; line coverage mostly confirms files are loaded.

Floors sit just under the achieved numbers so they ratchet. Raise them as the real figures move up; do not lower one to make a change pass. Branch is 95 rather than 100 because a handful of `&.` guards defend against states that cannot occur, and contorting tests to reach them proves nothing. Deliberate margin, not a knife edge at the actuals: a floor pinned to the exact current figure fails on refactors that change nothing about test quality. Because these are percentages, the absolute number of untested branches they permit grows with the codebase — **re-ratchet at each phase boundary**, not once. Requires SimpleCov >= 1.0, where the supported criteria are `[:line, :branch, :method, :oneshot_line]`; 0.x supports only line and branch.

A filtered run — one file, one example, or a tag selector — legitimately exercises less of the library, so the gate applies to full runs only. Otherwise the nightly `--tag integration` job would fail on coverage rather than on tests.

A threaded smoke spec for §5.2. A spec asserting no committed cassette contains unscrubbed secrets.

---

## 10. Repository, CI, and release engineering

- **CI (GitHub Actions):** `test.yml` — matrix `["3.2","3.3","3.4","4.0","head"]` (head: `continue-on-error`), RuboCop job, coverage artifact. `nightly.yml` — live TEST-env integration on schedule, creds from repo secrets. `release.yml` — tag-triggered, **RubyGems Trusted Publishing (OIDC)** — no long-lived API keys anywhere.
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

Build the **certificate flow first**: it is the only one that can bootstrap a credential from nothing, so it is what makes the nightly TEST suite self-sufficient and unblocks §12.4. The token flow then has something to authenticate with when minting its first token.

**Done when:** §8 contract runs against TEST; a KSeF token can be minted end-to-end by this gem with no external client; all seven types build, validate, round-trip.

**In progress, 2026-08-22.** The DSL is done — §8's snippet runs verbatim and validates. Of the certificate flow, the `AuthTokenRequest` document and the XAdES-BES signer are done and independently verified offline; the four HTTP calls of `docs/REFERENCE.md` §4.2 are not. Nothing has yet been sent to TEST, so none of the "Done when" gates is met.

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

1. Repo/org placement and gem author metadata (name, email, homepage).
2. XSD redistribution outcome (§7.7 tier 2) — bundle vs fetch-and-cache.
3. Default rounding strategy confirmation (`:per_line` proposed) once real accounting examples are in fixtures.
4. ~~Whether TEST-env credentials for nightly CI come from a dedicated test NIP (recommended) — needs human to provision via the TEST self-service tools.~~ **Resolved 2026-08-23.** A dedicated invented NIP, provisioned by `rake auth:bootstrap` (docs/REFERENCE.md §6a.3) rather than by hand. `KSEF_TEST_NIP` and `KSEF_TEST_TOKEN` are stored in the `ksef-test` environment and the nightly schedule is enabled. The run also confirmed that KSeF accepts this gem's XAdES signature (§6a.4).
5. Any trademark/naming sensitivities around "KSeF" in the gem description (likely none — official SDKs use it — but confirm before publishing).
