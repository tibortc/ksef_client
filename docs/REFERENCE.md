# Verification ledger

Every fact the implementation depends on, with its source and retrieval date, per
DESIGN.md §0.2 and §2. **Nothing about endpoint paths, XML element names, namespace
URIs or cryptographic parameters may enter the code unless it appears here.**

Entries are `value + source URL + date`. When this ledger and DESIGN.md disagree, the
ledger wins (DESIGN.md §2) — divergences are called out in §7 below.

---

## 1. Pinned artifacts

Upstream repository: **`CIRFMF/ksef-api`** — https://github.com/CIRFMF/ksef-api
Pinned at commit **`1c34fe2799387d517b83a2fb21e31e83d5f66247`** (authored 2026-07-21T15:11:33Z).
Retrieved **2026-08-21**.

Upstream licence: **MIT, © 2025 Ministerstwo Finansów** (`LICENSE.txt` at repo root,
retained here as `LICENSE.upstream.txt`).

| Local path | Upstream path | SHA-256 |
|---|---|---|
| `spec/fixtures/openapi/open-api.json` | `open-api.json` | `ef8afbbee719f2232f692d1553a7d13a7f4524945614c9c3df331149dd083651` |
| `lib/ksef/fa3/schema/schemat_FA(3)_v1-0E.xsd` | `faktury/schemy/FA/schemat_FA(3)_v1-0E.xsd` | `b646b6b525f51adf1bb2545f111fc8ca6e7aa6dd2f98948f1667d3695c06d958` |
| `lib/ksef/fa3/schema/bazowe/ElementarneTypyDanych_v10-0E.xsd` | `faktury/schemy/FA/bazowe/…` | `8daf4d3771de200b26b697294cc906a2add3de9acfbbd97f4b1bd4fc0e5ecb2f` |
| `lib/ksef/fa3/schema/bazowe/KodyKrajow_v10-0E.xsd` | `faktury/schemy/FA/bazowe/…` | `48be2a9f181d7ff80f185c62491ba12604c5cacbbe21af8e2aaaf2c585bbd214` |
| `lib/ksef/fa3/schema/bazowe/StrukturyDanych_v10-0E.xsd` | `faktury/schemy/FA/bazowe/…` | `cb08348374598e1e716e086c40d740390fb9e1bfa3aba1f4ec4cba0e1ef6d60f` |
| `lib/ksef/auth/schema/schemat_auth_v2-0.xsd` | `auth/schemy/schemat_auth_v2-0.xsd` | see `docs/artifacts.sha256` |
| `lib/ksef/auth/schema/schemat_auth_v2-1.xsd` | `auth/schemy/schemat_auth_v2-1.xsd` | see `docs/artifacts.sha256` |

`rake verify:artifacts` re-checks these digests; treat a mismatch as an upstream change,
not as a local bug.

### 1.1 Mirror vs. live spec

The committed `open-api.json` was compared against the spec each environment serves live
(2026-08-21). The GitHub mirror and the live TEST spec are **semantically identical** —
same 78 paths, same 302 component schemas; the small byte difference is formatting only.
The mirror is therefore safe to treat as the contract of record.

### 1.2 XSD redistribution — resolves DESIGN.md §12 open question 2

The schemas are published under the repository's MIT licence, which permits
redistribution. **Decision: bundle the XSD in the gem.** The first-run
fetch-and-cache fallback contemplated by DESIGN.md §7.7 tier 2 is not needed.

---

## 2. Environments — resolves DESIGN.md §6.1 [VERIFY]

Each base URL was read from **that environment's own OpenAPI document** (`servers[0].url`,
served at `https://<host>/docs/v2/openapi.json`), not inferred by analogy. Retrieved 2026-08-21.

| Env | Base URL | Spec title | Paths |
|---|---|---|---|
| `:test` | `https://api-test.ksef.mf.gov.pl/v2` | KSeF API TE | 78 |
| `:demo` | `https://api-demo.ksef.mf.gov.pl/v2` | KSeF API TR | 59 |
| `:prod` | `https://api.ksef.mf.gov.pl/v2` | KSeF API PR | 59 |

Corroborated by `srodowiska.md` (dated 16.03.2026), which lists the same three hosts.

**The base URL already contains `/v2`.** Endpoint paths are appended bare — the correct
challenge URL is `https://api-test.ksef.mf.gov.pl/v2/auth/challenge`. There is **no `/api`
segment** (see §7.2).

**Environment parity:** DEMO and PROD expose an identical path set. TEST adds 19 paths —
the `/testdata/*` helper API (15) and `/collective-identifiers*` (4). Code that targets
those paths must be guarded to TEST.

Format support (`srodowiska.md`): TEST accepts FA(2) and FA(3); DEMO and PROD accept
FA(3) only.

Operational note: the test environments undergo scheduled maintenance daily between
**16:00 and 18:00** local time; expect transient failures in nightly CI scheduled in that
window.

---

## 3. Endpoint paths (from the pinned spec)

Relative to the environment base URL above. Only the paths this gem targets are listed;
the spec carries 78 in total.

### Auth
| Method | Path |
|---|---|
| POST | `/auth/challenge` |
| POST | `/auth/ksef-token` |
| POST | `/auth/xades-signature` |
| POST | `/auth/token/redeem` |
| POST | `/auth/token/refresh` |
| GET | `/auth/{referenceNumber}` |
| GET | `/auth/sessions` |
| DELETE | `/auth/sessions/current` |
| DELETE | `/auth/sessions/{referenceNumber}` |

### Security / crypto
| Method | Path |
|---|---|
| GET | `/security/public-key-certificates` |

### Sessions
| Method | Path |
|---|---|
| POST | `/sessions/online` |
| POST | `/sessions/online/{referenceNumber}/invoices` |
| POST | `/sessions/online/{referenceNumber}/close` |
| POST | `/sessions/batch` |
| POST | `/sessions/batch/{referenceNumber}/close` |
| GET | `/sessions` |
| GET | `/sessions/{referenceNumber}` |
| GET | `/sessions/{referenceNumber}/invoices` |
| GET | `/sessions/{referenceNumber}/invoices/failed` |
| GET | `/sessions/{referenceNumber}/invoices/{invoiceReferenceNumber}` |

### UPO
| Method | Path |
|---|---|
| GET | `/sessions/{referenceNumber}/upo/{upoReferenceNumber}` |
| GET | `/sessions/{referenceNumber}/invoices/{invoiceReferenceNumber}/upo` |
| GET | `/sessions/{referenceNumber}/invoices/ksef/{ksefNumber}/upo` |

UPO is retrievable **both per session and per invoice** — resolves the DESIGN.md §2
[VERIFY] on UPO fetch granularity. Per-invoice UPO is addressable by either the invoice
reference number or the KSeF number.

### Invoices
| Method | Path |
|---|---|
| GET | `/invoices/ksef/{ksefNumber}` |
| POST | `/invoices/query/metadata` |
| POST | `/invoices/exports` |
| GET | `/invoices/exports/{referenceNumber}` |

### Limits
| Method | Path |
|---|---|
| GET | `/rate-limits` |
| GET | `/limits/context` |
| GET | `/limits/subject` |

---

## 4. Authentication

Source: `uwierzytelnianie.md` (10.07.2025) plus the pinned spec. Retrieved 2026-08-22.

- Security scheme: a single HTTP **`Bearer`** scheme, `bearerFormat: JWT`
  (`components.securitySchemes.Bearer`).
- **Exactly two authentication methods exist**, and both share the same challenge
  prologue and the same token-redemption epilogue:
  1. **Qualified electronic signature (XAdES)** — an `AuthTokenRequest` XML document
     signed with a certificate. The authenticating subject is read *from the signing
     certificate*. `POST /auth/xades-signature`, `Content-Type: application/xml`.
  2. **KSeF token** — a JSON document carrying a previously issued token.
     `POST /auth/ksef-token`.
- `POST /auth/challenge` returns `AuthenticationChallengeResponse`, required fields:
  `challenge`, `timestamp` (date-time), `timestampMs` (int64, Unix ms), `clientIp`.
- **Challenge lifetime is 10 minutes** — now *verified* from `uwierzytelnianie.md`
  ("Czas życia challenge'a wynosi 10 minut"), superseding the earlier note in this
  section that it was documentation-hearsay and unconfirmed.
- `clientIp` in the challenge response ties into the `ip-not-allowed` authorisation
  failure (§5.3): the API pins the session to the IP seen at authentication.
- The authenticating subject must already hold at least one active permission in the
  requested context, or no access token is issued.

### 4.1 The `AuthTokenRequest` document

Pinned at `lib/ksef/auth/schema/schemat_auth_v2-{0,1}.xsd` (§1). Both versions are
accepted by the API; v2.1 is current.

| Fact | Value |
|---|---|
| Target namespace (v2.1) | `http://ksef.mf.gov.pl/auth/token/2.1` |
| `elementFormDefault` | `qualified` |
| Root element | `AuthTokenRequest` |
| Required children | `Challenge`, `ContextIdentifier`, `SubjectIdentifierType` |
| `SubjectIdentifierType` values | `certificateSubject`, `certificateFingerprint` |
| Optional | `AuthorizationPolicy` → `AllowedIps` (`Ip4Address`, `Ip4Range`) |

`ContextIdentifier` may be a NIP, an internal identifier, or a composite VAT-UE
identifier. Signature form: enveloped or enveloping; **detached is rejected**.

Self-signed certificates are accepted on **TEST only**. `srodowiska.md` is explicit that
this is why TEST contexts are not isolated between integrators.

### 4.2 Tokens

`/auth/token/redeem` exchanges a completed authentication for the token pair;
`/auth/token/refresh` renews. This confirms the DESIGN.md §6.3 step 4 [VERIFY] — the API
does issue a refresh token alongside the access token.

| Token | Lifetime | Notes |
|---|---|---|
| `accessToken` | short, expiry in the JWT `exp` claim (docs say "kilkanaście minut") | sent as `Authorization: Bearer` |
| `refreshToken` | **up to 7 days**, reusable | renews the access token without re-authenticating |

**Revocation is not immediate.** An `accessToken` stays valid until its `exp` even if the
user's permissions change in the meantime. Never treat possession of a live token as
proof of current authorisation.

---

## 5. Error model — resolves DESIGN.md §6.7 [VERIFY]

### 5.1 Two envelopes; the *request* opts in

Error bodies come in two shapes. The modern one is **opt-in via a request header**:

```
X-Error-Format: problem-details
```

All **83** operations in the pinned spec document this header, with the wording
"ustawienie tego nagłówka powoduje zwracanie błędów w formacie Problem Details" —
*setting this header causes errors to be returned in Problem Details format*. Without it
the API returns the deprecated `application/json` shapes, which carry no `traceId`, no
structured `errors[]` codes on 400 and no `reasonCode` on 403. `Ksef::HTTP::Connection`
therefore sends it on every request.

The response `Content-Type` then reflects which envelope you got:

| Content type | 400 | 429 | Status |
|---|---|---|---|
| `application/problem+json` | `BadRequestProblemDetails` | `TooManyRequestsProblemDetails` | **current** |
| `application/json` | `ExceptionResponse` | `TooManyRequestsResponse` | **deprecated** (`deprecated: true` in the spec) |

401, 403 and 410 are declared **only** as `application/problem+json`.

The parser must prefer the problem+json shape and fall back to the legacy shapes, which
nest differently — `ExceptionResponse` under `exception.exceptionDetailList[]`, and
`TooManyRequestsResponse` under `status.details[]`. `limity/limity-api.md` still documents
the legacy 429 body, so both are live in the wild.

### 5.2 problem+json common fields

`title`, `status`, `detail`, `instance`, `timestamp` (UTC date-time), `traceId`.
`traceId` should be surfaced on every error — it is what the Ministry's support asks for.

400 additionally carries `errors[]` of **`ApiError`**: `code` (int32), `description`,
`details[]` (nullable). This is the machine-readable error-code catalogue —
`code` maps to `Ksef::ApiError#code`. Observed examples: `21405` (input validation
failure), `21157` (invalid package part size).

### 5.3 403 carries a structured reason

`ForbiddenProblemDetails` adds a required **`reasonCode`** plus a `reasonCode`-dependent
`security` object:

| `reasonCode` | `security` payload |
|---|---|
| `missing-permissions` | `requiredAnyOfPermissions: string[]`, `presentPermissions: string[]` |
| `ip-not-allowed` | `clientIp: string` |
| `insufficient-resource-access` | — |
| `auth-method-not-allowed` | `authenticationMethodCategory: string` |
| `security-service-blocked` | `incidentId: string`, `clientIp: string` |
| `context-type-not-allowed` | `contextIdentifierType: string` |

### 5.4 Status codes actually declared

`400` (83 ops), `401` (68), `403` (68), `410` (4), `429` (80). Success: `200` (59),
`201` (4), `202` (14), `204` (6).

**No 5xx is declared anywhere in the spec.** A `ServerError` branch is still required
defensively — infrastructure returns 5xx regardless of contract — but it cannot be
mapped to a documented payload shape and must degrade to the raw body.

### 5.5 Response headers

| Header | Where | Meaning |
|---|---|---|
| `Retry-After` | every one of the 80 `429` responses | **seconds** to wait; authoritative, honour it over any computed backoff |
| `X-System-Warning` | all `200`/`201`/`202`/`204` responses | advisory system notice; surface via the instrumentation hook |
| `x-ms-meta-hash` | 4 × `200` (export/download) | Azure blob content hash on downloaded artifacts |

`Retry-After` confirms the DESIGN.md §6.7 [VERIFY]. `X-System-Warning` is not mentioned
in DESIGN.md and is worth propagating — it is the Ministry's in-band deprecation channel.

---

## 6. Rate limits — DESIGN.md §6.7 retry policy input

Source: `limity/limity-api.md` (dated 22.11.2025), retrieved 2026-08-21.

- Limits are counted per **(context, client IP)** pair, where context is the
  `ContextIdentifier` (`Nip`, `InternalId` or `NipVatUe`) presented at authentication.
  The same context from two IPs gets two independent budgets.
- Enforcement uses a **sliding window**, not a fixed one: req/s over the trailing second,
  req/min over the trailing 60 seconds, req/h over the trailing 60 minutes. Windows do
  **not** reset on the minute or hour. All thresholds apply simultaneously; the first one
  crossed triggers the block.
- On breach the API returns **429** and blocks further requests for a **dynamic** period
  that lengthens with repeat offences. The exact duration is in `Retry-After`.
- Per-endpoint ceilings are documented per operation in the spec (e.g. `/auth/challenge`
  is 60 req/s).
- Repeated breaches are recorded and analysed; the docs explicitly flag spreading one
  context across many IPs as an abuse pattern. **The client must never work around a 429
  by rotating connections.**

Live budgets are introspectable at runtime via `GET /rate-limits`, `GET /limits/context`
and `GET /limits/subject`.

---

## 6a. Provisioning TEST credentials (DESIGN.md §12.4)

Sources: `dane-testowe-scenariusze.md` (05.08.2025), `tokeny-ksef.md` (29.06.2025),
`srodowiska.md`, and the pinned spec. Retrieved 2026-08-22.

### 6a.1 There is no NIP to "obtain" — you invent one

`srodowiska.md` is explicit: use **random** NIPs on TEST and avoid any real data. TEST
permits self-signed certificates, so many integrators authenticate in the same company
context and **TEST data is not isolated between them**.

A test NIP must still pass the standard checksum: digits 1–9 weighted by
`6,5,7,2,3,4,5,6,7`, summed, `mod 11`, which must equal digit 10 (and must not be 10).
Verified against every NIP appearing in the upstream docs — `7762811692`, `7980332920`,
`3755747347` — and against the two in DESIGN.md §8, `9999999999` and `1111111111`. All
six are checksum-valid, which independently confirms the §7.2 algorithm.

You then register the NIP on TEST:

| Endpoint | Use |
|---|---|
| `POST /testdata/subject` | Legal entities. Body: `subjectNip`, `subjectType`, `description` (5–256 chars), optional `subunits`. Supports VAT-group and JST hierarchies. |
| `POST /testdata/person` | Natural persons. Body: `nip`, `pesel`, `description`, `isBailiff`. Grants **Owner** (plus `EnforcementOperations` when `isBailiff: true`). |

**These `/testdata/*` endpoints require no authentication.** The spec declares no global
`security` and these operations declare none of their own — so bootstrapping a context
needs no prior credentials. (They exist on TEST only; see §2.)

`createdDate` caveat: when re-creating test data under the same identifier, the date must
be **later** than the previous one — not equal, not earlier.

### 6a.2 The token needs a one-time XAdES authentication — this blocks §12.4 for 0.1

`tokeny-ksef.md`: *"Wygenerowanie tokena KSeF jest możliwe wyłącznie po jednorazowym
uwierzytelnieniu się podpisem elektronicznym (XAdES)."* — a KSeF token can be generated
**only** after a one-time authentication with a qualified electronic signature.

The pinned spec corroborates it: `POST /tokens` declares `security: [{Bearer: []}]`, so it
needs an existing session, while `/auth/xades-signature` needs none. There is no
unauthenticated path to a first token.

**Consequence for this gem — and why the roadmap changed.** This finding is what moved
XAdES from 0.3 into 0.1 (DESIGN.md §6.3, decided 2026-08-22). A token-only client cannot
issue its own first credential, which would have forced every user — and our own nightly
CI — to bootstrap via somebody else's client.

Until the certificate flow is implemented, the interim workaround is a one-time
out-of-band mint via the official `ksef-client-csharp`, using a self-signed certificate
(permitted on TEST; see `auth/testowe-certyfikaty-i-podpisy-xades.md`). Once §6.3's
certificate flow lands, this gem mints its own and the workaround is retired.

Tokens are minted in a `Nip` or `InternalId` context with a fixed permission set chosen at
creation — changing permissions requires a new token. For this gem's integration suite,
`InvoiceRead` and `InvoiceWrite` are the relevant ones. Treat the token as a confidential
secret (`tokeny-ksef.md` says so explicitly).

---

## 7. Divergences from DESIGN.md

Recorded per DESIGN.md §2 ("when the pinned artifacts and this document disagree, the
artifacts win"). These need noting in the PR description.

1. **`ksef-docs` does not exist.** DESIGN.md §2 names `CIRFMF/ksef-docs` as the developer
   compendium. The `CIRFMF` org contains `ksef-api`, `ksef-client-csharp`,
   `ksef-client-java`, `ksef-pdf-generator`, `ksef-latarnia` and `ksef-schematy` — no
   `ksef-docs`. All prose documentation **and** the OpenAPI spec **and** the FA(3)
   schemas live in **`ksef-api`**. (`ksef-schematy` is a discussion repo — README only.)

2. **No `/api` path prefix.** DESIGN.md §2 gives approximate shapes
   `POST /api/v2/auth/challenge` and `POST /api/v2/auth/xades-signature`. The real
   contract is base URL `…/v2` + `/auth/challenge`. Building URLs with `/api/v2` would
   404 every call.

3. **`KodFormularza` value is `FA`, not `FA (3)`.** See §8 — `FA (3)` is the value of the
   `kodSystemowy` attribute, not the element's text content. Easy to conflate.

4. **DESIGN.md §6.7's hierarchy omits 403 and 410**, both of which the API returns. 403 in
   particular carries structured, actionable data (§5.3) that deserves its own error
   class rather than collapsing into a generic `ApiError`.

5. **DESIGN.md §6.7 anticipates a 5xx branch** that the spec never declares (§5.4). Keep
   the branch, but do not expect a documented payload.

---

## 8. FA(3) schema facts

Source: pinned `schemat_FA(3)_v1-0E.xsd` (§1).

| Fact | Value |
|---|---|
| Target namespace | `http://crd.gov.pl/wzor/2025/06/25/13775/` |
| Imported namespace | `http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2022/01/05/eD/DefinicjeTypy/` |
| `elementFormDefault` | `qualified` |
| `attributeFormDefault` | `unqualified` |
| `KodFormularza` element value | `FA` (only member of `TKodFormularza`) |
| `KodFormularza/@kodSystemowy` | `FA (3)` — required, fixed. Note the space before `(` |
| `KodFormularza/@wersjaSchemy` | `1-0E` — required, fixed |
| `WariantFormularza` | `3` (xsd:byte, single enumeration) |
| `DataWytworzeniaFa` range | `2025-09-01T00:00:00Z` … `2050-01-01T23:59:59Z` |

`elementFormDefault="qualified"` means **every** element must be namespace-qualified in
the instance document — the serializer cannot emit unprefixed children.

### 8.1 Structural shape (measured 2026-08-22, drives the codegen)

The schema is not a flat set of named types, which is what a reader might reasonably
expect. Counts below are from the pinned file and are asserted by
`spec/ksef/fa3/generated_spec.rb`.

| Fact | Value |
|---|---|
| Global elements | 1 (`Faktura`) |
| Named complexTypes | 7 |
| Anonymous complexTypes reachable from the root | 51 |
| Max nesting depth | 7 |
| `xsd:sequence` | 86 |
| `xsd:choice` | 19 |
| `xsd:all` / `xsd:group` / `xsd:any` | 0 |
| Named simpleTypes with enumerations | 21 across all pinned schemas |
| `xsd:simpleContent` extensions | 2 |

Two consequences the generator has to honour:

1. **Leaf element names are not unique.** `DaneKontaktowe` appears under all four subject
   elements, so generated metadata is keyed by element *path*
   (`Faktura/Podmiot1/DaneKontaktowe`), which also stays stable if upstream adds a fifth.
2. **Four types have a top-level `xsd:choice`** — `Zwolnienie`, `NoweSrodkiTransportu`,
   `PMarzy` and `FakturaZaliczkowa` (all reached via `Faktura/Fa/...`). Anything that
   flattens a type's root compositor converts their "exactly one of" into "all of these,
   in order", which a validator would then accept. Choice structure must be preserved,
   not flattened.

`TStawkaPodatku` has 14 values and **half of them are not numeric** — seven rates
(`23`, `22`, `8`, `7`, `5`, `4`, `3`) alongside seven codes (`0 KR`, `0 WDT`, `0 EX`,
`zw`, `oo`, `np I`, `np II`). Any numeric coercion in the VAT path corrupts the latter,
so rate codes are carried as strings throughout and only the *amounts* are `BigDecimal`.

### 8.2 Import chain and offline validation

```
schemat_FA(3)_v1-0E.xsd
  └─ import  http://crd.gov.pl/…/StrukturyDanych_v10-0E.xsd   ← absolute remote URL
                └─ include ElementarneTypyDanych_v10-0E.xsd   ← relative
                              └─ include KodyKrajow_v10-0E.xsd ← relative
```

Only the top-level import is an absolute `http://crd.gov.pl/…` URL; the two nested
includes are relative and resolve inside `bazowe/`.

**Consequence:** compiling this XSD as-is makes Nokogiri attempt a network fetch of
`crd.gov.pl` at validation time — unacceptable for an offline, deterministic test suite.
The validator must rewrite that one `schemaLocation` to the local `bazowe/` copy **in
memory**, parsing the XSD into a document, editing the attribute, and compiling with a
base URI pointing at the schema directory. The pinned file on disk must stay byte-for-byte
identical so the §1 digests keep verifying.

---

## 9. Still unverified

Carried forward; must be resolved before the code that depends on them is written
(DESIGN.md §0.2).

- **Crypto parameters** (DESIGN.md §6.4): symmetric cipher mode/padding/IV convention,
  RSA-OAEP digest and MGF1 parameters for both key wrapping and token encryption, and
  which published certificate serves which purpose. Sources to mine:
  `bezpieczenstwo/klucze-publiczne-do-szyfrowania.md`, `tokeny-ksef.md`, and the
  `ksef-client-csharp` reference implementation for golden vectors.
- **Session semantics**: whether one online session may carry multiple invoices, and
  session lifetime. Source: `sesja-interaktywna.md`.
- **JWT lifetime and refresh mechanics**. Source: `uwierzytelnianie.md` plus the
  `/auth/token/refresh` response model.
- **Challenge 10-minute validity** — asserted in DESIGN.md, not found in the spec (§4).
- **P_13_x / P_14_x rate-bucket ↔ VAT-rate mapping** (DESIGN.md §7.3). Source: the pinned
  XSD plus `faktury/` guidance.
- **Business-rule catalogue** for validation tier 3 (DESIGN.md §7.7).
- **UPO document format** — schema pinned upstream at `faktury/upo/schemy/upo-v4-3.xsd`
  with worked examples under `faktury/upo/przyklady/v4-3/`; not yet pulled in.
