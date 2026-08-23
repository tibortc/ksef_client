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

**This reasoning does not generalise to every schema in the repository, and the
distinction is load-bearing.** It holds for the FA(3), auth and UPO schemas, which are the
Ministry's own work and therefore covered by its MIT licence. It does *not* hold for the
W3C, OASIS and ETSI schemas that upstream redistributes inside its PEF bundle — the
Ministry's licence cannot relicense someone else's document. Those are pinned to
`spec/fixtures/xades/` and deliberately **not** packaged; see §4.3. Two questions decide
where a pinned schema goes:

1. **Is it needed at runtime, or only by the tests?** Test-only artifacts belong in
   `spec/fixtures/` regardless of licence, because shipping them is dead weight.
2. **Whose document is it?** If the answer is not "Ministerstwo Finansów", this section's
   MIT reasoning does not apply and bundling needs its own justification.

Anything that would move a third-party schema into `lib/` — for instance offering runtime
signature validation — is a licensing decision, not a refactor, and belongs with the human
(DESIGN.md §12).

### 1.3 Pinned prose documentation

`ksef-api` holds **77 files**; the four schemas and the OpenAPI document above were
originally the only ones pinned. That was a mistake: most of what §9 listed as
"unverified" was sitting in the same repository, in prose. The normative subset is now
mirrored under `docs/upstream/`, preserving upstream paths, at the **same commit
`1c34fe27`**. Verified byte-for-byte against the upstream tree listing on download.

| Local path (under `docs/upstream/`) | Feeds |
|---|---|
| `uwierzytelnianie.md` | §4, §4.3, §4.5 — the whole auth flow |
| `auth/podpis-xades.md` | §4.3, §4.4 — XAdES allow-list, certificate attributes |
| `auth/testowe-certyfikaty-i-podpisy-xades.md` | §4.6 — TEST bootstrap |
| `auth/sesje.md` | §4.7 — auth session revocation |
| `auth/context-identifier-*.md`, `auth/subject-identifier-type-*.md` | §4.1 — verbatim request examples |
| `bezpieczenstwo/klucze-publiczne-do-szyfrowania.md` | §10.2 — key distribution and rotation |
| `sesja-interaktywna.md` | §11 — online session semantics |
| `faktury/sesje/sesja-sprawdzenie-stanu-i-pobranie-upo.md` | §12 — status and UPO retrieval |
| `faktury/numer-ksef.md` | §13 — KSeF number structure and CRC-8 |
| `limity/limity-api.md`, `limity/limity.md` | §6, §6.1 — rate and size limits |
| `srodowiska.md` | §2, §11.3 — environments, accepted schema versions |
| `dane-testowe-scenariusze.md` | §6a — TEST data provisioning |

The UPO schema is pinned to `lib/ksef/upo/schema/upo-v4-3.xsd` (in `lib/`, following the
precedent set by the auth schemas: pinned ahead of the code that consumes it) and the six
worked UPO examples to `spec/fixtures/upo/`.

Two entries share a digest — `auth/context-identifier-nip.md` and
`auth/subject-identifier-type-certificate-subject.md` are byte-identical upstream, both
illustrating the same NIP-plus-`certificateSubject` request. That is not a download error.

**Deliberately not pinned yet:** `uprawnienia.md` (68 KB, permissions API → 0.2),
`api-changelog.md` (76 KB), `certyfikaty-KSeF.md` (KSeF certificate lifecycle → 0.3),
`kody-qr.md` and `qr/` (→ 0.3), `offline/`, `pobieranie-faktur/`, `sesja-wsadowa.md`
(batch → 0.2), and the PEF / RR / FA(2) schemas. Prose churns on editorial fixes, and a
`verify:artifacts` failure should mean *a fact changed*, not that someone corrected a
typo — so only documents this milestone actually derives facts from are in the manifest.

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

Pinned at `lib/ksef/auth/schema/schemat_auth_v2-{0,1}.xsd` (§1).

**Send the 2.0 namespace.** An earlier revision of this section said "both versions are
accepted by the API; v2.1 is current" and this gem was built against 2.1 on that basis.
That was an inference, not a verified fact, and checking the reference implementations
(2026-08-22) contradicted it — see §14.4. Every piece of available evidence points at 2.0:

| Source | Namespace |
|---|---|
| `ksef-client-csharp`, `AuthenticationTokenRequest.cs` | `[XmlRoot(Namespace = "…/auth/token/2.0")]` |
| `ksef-client-java`, JAXB-generated `TContextIdentifier` etc. | generated against `…/2.0` |
| `ksef-client-java`, its own bundled `AuthTokenRequest.xsd` | `targetNamespace="…/2.0"` |
| all five worked examples in `CIRFMF/ksef-api` | `xmlns="…/2.0"` |

Nothing observed emits 2.1. **Whether the API accepts 2.1 at all is unverified** and needs
a live TEST call; until then 2.0 is the only defensible default.

Validation is a separate question from what to send, because **v2.0's file does not compile
as a schema** (§14.4). The rules therefore come from v2.1's file with its target namespace
rewritten in memory to match the document — the same technique `Ksef::FA3::Validator` uses
for its remote `schemaLocation`, and legitimate here because the two files are structurally
identical: diffing them shows only the namespace and the three IP patterns differ, and
v2.1's are the correct ones.

| Fact | Value |
|---|---|
| Target namespace (v2.1) | `http://ksef.mf.gov.pl/auth/token/2.1` |
| `elementFormDefault` | `qualified`; `attributeFormDefault` `unqualified` |
| Root element | `AuthTokenRequest` (no namespace prefix in upstream's examples — default namespace) |
| Required children, in order | `Challenge`, `ContextIdentifier`, `SubjectIdentifierType` |
| `SubjectIdentifierType` values | `certificateSubject`, `certificateFingerprint` |
| Optional | `AuthorizationPolicy` → `AllowedIps` → `Ip4Address` / `Ip4Range` / `Ip4Mask`, each 0–**10** |

`AllowedIps` is itself mandatory *inside* `AuthorizationPolicy`, so the policy element
cannot be present but empty.

**`Challenge` is strictly formatted** — `xsd:token`, length exactly **36**, pattern
`\d{8}-CR-[A-F0-9]{10}-[A-F0-9]{10}-[A-F0-9]{2}`. Verified 2026-08-22 that upstream's own
example `20250604-CR-461EA5B000-537A6BA15D-D7` satisfies it, that lowercase hex is
rejected, and that the literal `CR` is required. Worth validating client-side before
spending a signature on it. Note the shape matches §12's reference numbers, `CR` being the
kind tag for a challenge.

`ContextIdentifier` is a **choice of four** in v2.1 — not three:

| Element | Pattern | Usable? |
|---|---|---|
| `Nip` | `[1-9]((\d[1-9])\|([1-9]\d))\d{7}` | yes |
| `InternalId` | the NIP pattern, then `-\d{5}` | yes |
| `NipVatUe` | NIP, `-`, then an EU VAT number by member state | **no — see §14.4** |
| `PeppolId` | `^P[A-Z]{2}[0-9]{6}$` | **no — see §14.4** |

Note the NIP pattern here is *structural* (first digit non-zero, positions 2–3 not both
zero), not a checksum. It is weaker than `Ksef::FA3::NIP`'s check-digit validation, so
both are worth applying.

Per `tokeny-ksef.md`, a KSeF token can only be issued in a **`Nip` or `InternalId`**
context, which is fortunate given the state of the other two.

Signature form: enveloped or enveloping; **detached is rejected**.

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

**`/auth/token/redeem` is single-use.** `uwierzytelnianie.md` §4: the endpoint returns the
token pair *once* for a completed authentication, and every subsequent call with the same
`authenticationToken` returns **400**. A retry wrapper around redemption would turn a
transient network blip into a permanently unusable authentication — this endpoint must
surface its errors, which the POST-never-retried rule (DESIGN.md §6.7) already guarantees.

The full flow, verified end to end from `uwierzytelnianie.md` (retrieved 2026-08-22):

| Step | Call | Auth header | Notes |
|---|---|---|---|
| 1 | `POST /auth/challenge` | none | public endpoint, 60 req/s per IP; TTL 10 min |
| 2 | build + sign `AuthTokenRequest` | — | offline |
| 3 | `POST /auth/xades-signature` | none | returns `referenceNumber` + `authenticationToken` |
| 4 | `GET /auth/{referenceNumber}` | `Bearer {authenticationToken}` | poll to completion |
| 5 | `POST /auth/token/redeem` | `Bearer {authenticationToken}` | **once only** → `accessToken` + `refreshToken` |
| 6 | `POST /auth/token/refresh` | `Bearer {refreshToken}` | renews `accessToken` |

Note the header at steps 4–5 is the *temporary* `authenticationToken`, not an
`accessToken`. Conflating them is the obvious implementation error here.

**Step 4 must poll without a deadline on DEMO and PROD.** Those environments verify the
signing certificate's status with the issuer over OCSP/CRL, and the operation legitimately
reports "in progress" until the issuer answers — the docs state the duration depends on the
certificate provider. A client that gives up after a fixed timeout will report failure for
authentications that were about to succeed. (On TEST, self-signed certificates skip this.)

### 4.3 XAdES signature requirements — resolves the §9 blocker

Source: `auth/podpis-xades.md`. **The specification is an allow-list, not a single
mandated combination**, which is the key finding: there is no exact byte-shape to
reverse-engineer, only a permitted set to choose from.

| Aspect | Permitted |
|---|---|
| Form | **enveloped** or **enveloping**. Detached is rejected. |
| Profiles | XAdES-BES, -EPES, -T, -LT, -C, -X, -XL, -A, -ERS, and BASELINE-B/-T/-LT/-LTA |
| Transforms | XPath `not(ancestor-or-self::ds:Signature)`, xmldsig-filter2, `#enveloped-signature`, `#base64`, c14n11 (±comments), exc-c14n (±comments), REC-xml-c14n-20010315 (±comments) |
| `SignatureMethod` | RSASSA-PKCS1-v1_5 or RSASSA-PSS (sha1/256/384/512, plus sha3-\* for PSS), min **2048-bit**; or ECDSA (sha1/256/384/512, sha3-\*), min **256-bit** curve |
| `DigestMethod` | sha1, sha256, sha384, sha512, sha3-256, sha3-384, sha3-512 — chosen **independently** of `SignatureMethod` |

`DigestMethod` governs both `SignedInfo/Reference/DigestMethod` and the qualifying
properties, notably `SigningCertificate/CertDigest/DigestMethod`.

**Implementation choice for this gem:** enveloped, XAdES-BES, `#enveloped-signature`
transform, exclusive c14n, `rsa-sha256`, `xmlenc#sha256` digest. Every one of those is
explicitly listed above, so the combination needs no further verification. Corroborated
2026-08-22 against both clients: C# builds exactly this shape in `SignatureService`, and
Java asks DSS for `SignaturePackaging.ENVELOPED` with `DigestAlgorithm.SHA256` and
`SignatureAlgorithm.RSA_SHA256`.

Neither client states its `SignedInfo` `CanonicalizationMethod` — C# leaves .NET's
`SignedXml` default in place and Java leaves it to DSS — so exclusive c14n is *this gem's*
choice rather than a copied one. It is safe because the allow-list above permits both c14n
1.0 and exclusive c14n, and exclusive avoids namespace-inheritance surprises when the
signature is lifted between documents.

#### Two facts the allow-list does not state

Both taken from `ksef-client-csharp`'s `KSeF.Client/Api/Services/SignatureService.cs`
(retrieved 2026-08-22) and recorded with that provenance rather than treated as common
knowledge:

| Fact | Value | Why it matters |
|---|---|---|
| `Type` on the `SignedProperties` reference | `http://uri.etsi.org/01903#SignedProperties` | Fixed by ETSI TS 101 903, absent from the Ministry's allow-list, and appears in no pinned artifact |
| `SigningTime` is **backdated one minute** | `CertificateTimeBuffer = TimeSpan.FromMinutes(-1)` | Unexplained upstream, but plainly a clock-skew guard: a signing time fractionally in the future relative to the server's clock invites rejection, and being a minute early costs nothing |

The remaining structural details, all mirrored: `Id="Signature"` and
`Id="SignedProperties"` as literal identifiers; the document reference is `URI=""` with the
enveloped transform *then* c14n; the `SignedProperties` reference carries only the c14n
transform; `KeyInfo` holds `X509Data/X509Certificate`; `IssuerSerial` uses the issuer name
in RFC 2253 order and the serial in decimal.

**One namespace subtlety worth stating explicitly**, because getting it wrong produces a
document that looks correct and verifies nowhere: inside `xades:QualifyingProperties` the
reference implementation declares `xmlns` = the **xmldsig** namespace, so `DigestMethod`,
`DigestValue`, `X509IssuerName` and `X509SerialNumber` are written *unprefixed* yet belong
to xmldsig, not to XAdES — even though they sit inside `xades:CertDigest` and
`xades:IssuerSerial`.

**Built directly on Nokogiri and stdlib `openssl`, adding no dependency.** Decided
2026-08-22 after confirming every primitive the signature and §10 need is already
available (measured, both on 3.2.11 and 4.0.6):

| Need | Available as |
|---|---|
| Exclusive c14n | `Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0` (also `_1_0` = 0 and `_1_1` = 2) via `Node#canonicalize` |
| `rsa-sha256` signature | `OpenSSL::PKey::RSA#sign("SHA256", …)` — 256-byte output for a 2048-bit key |
| RSA-OAEP SHA-256 + MGF1-SHA-256 | `#encrypt(data, rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256")` — the plain `#public_encrypt` will **not** do, it cannot set the MGF1 digest |
| AES-256-CBC / PKCS#7 | `OpenSSL::Cipher.new("aes-256-cbc")`, padding on by default; `#random_key` / `#random_iv` give the 32 and 16 bytes of §10.1 |

`openssl` is a **default gem** on both Rubies (3.1.0 on 3.2.11, 4.0.2 on 4.0.6), so
requiring it is not a new runtime dependency and needs no gemspec entry — the same status
as `date`, and unlike `bigdecimal`, which had to be declared because it became a *bundled*
gem in Ruby 3.4.

#### Signature namespaces, and where they are pinned

Read from pinned artifacts rather than recalled, per the never-invent-a-namespace-URI rule.
Upstream redistributes the W3C and ETSI schemas inside its PEF bundle, so they are
available at the same commit as everything else:

| Namespace | Pinned as |
|---|---|
| `http://www.w3.org/2000/09/xmldsig#` | `spec/fixtures/xades/UBL-xmldsig-core-schema-2.1.xsd` |
| `http://uri.etsi.org/01903/v1.3.2#` | `spec/fixtures/xades/UBL-XAdESv132-2.1.xsd` |
| `http://uri.etsi.org/01903/v1.4.1#` | `spec/fixtures/xades/UBL-XAdESv141-2.1.xsd` |

Measured 2026-08-22: all three **compile offline**. Their `xsd:import` locations are
*relative* (`UBL-xmldsig-core-schema-2.1.xsd`), so unlike the FA(3) schema they need no
in-memory `schemaLocation` rewrite, and `xmldsig-core` imports nothing at all. A minimal
enveloped `ds:Signature` using exclusive c14n, `rsa-sha256` and `xmlenc#sha256` validates
against the xmldsig schema, and the same document with `SignatureValue` removed is
rejected — so this gives the signer real structural validation, not a rubber stamp.

**Placed under `spec/fixtures/`, not `lib/`, on purpose.** Two reasons. Validating a
signature is a test-time concern — the client signs, and KSeF verifies — so nothing at
runtime needs these files. And they are W3C and ETSI documents redistributed by OASIS and
then by the Ministry; their terms are not the repository's MIT licence that §1.2 relied on
for bundling the FA(3) schemas. Keeping them out of the gem sidesteps a redistribution
question we do not need to answer.

`ksef-client-csharp`'s `CertTestApp` (§4.6) is held in reserve as a debugging aid, not a
build-time input: if TEST rejects a signature with a message that does not say why, its
`--output file` signed XML gives something concrete to diff against. Installing a .NET SDK
is therefore optional, and deliberately not a prerequisite for this work.

For ECDSA, `SignatureValue` is `R || S` fixed-field concatenation per XMLDSIG 1.1 /
RFC 4050 §3.3 — **not** DER, which is what OpenSSL emits by default. Only relevant if
ECDSA support is added; RSA avoids the issue.

### 4.4 Certificate subject requirements

Source: `auth/podpis-xades.md`. Accepted certificate types: qualified personal (PESEL or
NIP), qualified organisation seal (NIP), Trusted Profile (ePUAP), KSeF-issued internal
certificate (not qualified, but honoured), and Peppol service-provider certificates.

| Certificate kind | Required subject attributes | Identifier pattern |
|---|---|---|
| Qualified personal signature | `givenName` (2.5.4.42), `surname` (2.5.4.4), `serialNumber` (2.5.4.5), `commonName` (2.5.4.3), `countryName` (2.5.4.6) | `(PNOPL\|PESEL).*?(\d{11})` or `(TINPL\|NIP).*?(\d{10})` |
| Qualified organisation seal | `organizationName` (2.5.4.10), `organizationIdentifier` (2.5.4.97), `commonName`, `countryName` | `(VATPL).*?(\d{10})` |

An organisation seal **must not** carry `givenName` or `surname`. The `.*?` in each
pattern accommodates the hyphenated form the reference clients emit — `TINPL-1234567890`,
`VATPL-1234567890`.

Where a qualified certificate lacks a usable identifier in 2.5.4.5, authentication is
still possible by pre-granting permissions against the certificate's **SHA-256
fingerprint** and using `SubjectIdentifierType` = `certificateFingerprint`.

### 4.5 KSeF-token authentication — the encrypted payload

Source: `uwierzytelnianie.md` §2.2. The plaintext is:

```
{ksefToken}|{timestampMs}
```

UTF-8 encoded, where `timestampMs` is the `timestamp` from the `POST /auth/challenge`
response **as Unix milliseconds**. Encrypt with the KSeF public key using
**RSA-OAEP with SHA-256 and MGF1-SHA-256**, then Base64-encode into `encryptedToken`.

The timestamp is not decoration — the docs are explicit that it acts as a nonce, so that a
captured ciphertext cannot be replayed into a later session. Reusing a stale timestamp, or
sending a locally generated one, defeats that and will not match the challenge.

`ECDsa` exists as an alternative encryption method in both reference clients. Out of scope
for 0.1; RSA is the documented default.

### 4.6 TEST bootstrap — resolves DESIGN.md §12.4's central unknown

Source: `auth/testowe-certyfikaty-i-podpisy-xades.md`.

**Self-signed certificates are permitted on TEST only**, and upstream ships a console app
that does the whole bootstrap: `KSeF.Client.Tests.CertTestApp`. It generates a test
certificate, builds and XAdES-signs `AuthTokenRequest`, submits it, polls to completion,
and returns the JWT pair. `--output file` writes both the certificate and the **signed
XML** to disk, which is exactly the reference artifact needed to check our own signature
against.

The document instructs installing .NET 10, but the project multi-targets
`net8.0;net9.0;net10.0` (`KSeF.Client.Tests.CertTestApp.csproj` @ `ksef-client-csharp`,
retrieved 2026-08-22), so any of those SDKs suffices.

### 4.7 Auth session management

Source: `auth/sesje.md`. `GET /auth/sessions` lists active authentication sessions
(`continuationToken` paging). `DELETE /auth/sessions/current` and
`DELETE /auth/sessions/{referenceNumber}` revoke one.

Revocation invalidates the associated **`refreshToken` only** — already-issued
`accessToken`s stay valid to their `exp`. Consistent with §4.2: there is no way to kill a
live access token.


### 4.8 Authentication status codes

`GET /auth/{referenceNumber}` returns **HTTP 200** carrying a `StatusInfo` whose `code` is
*not* an HTTP status — it describes the asynchronous operation. The Ministry's prose names
only "in progress" and "succeeded", and says outright that the full list "will be available
in the endpoint's technical documentation".

Source: `KSeF.Client.Core/Models/ApiResponses/AuthenticationStatusCodeResponse.cs` in
`ksef-client-csharp`, retrieved 2026-08-22. Recorded with that provenance: this is a
reference-implementation constant, not something the contract states.

| Code | Meaning | Terminal? |
|---|---|---|
| 100 | authentication in progress | no — the only code that means keep polling |
| 200 | succeeded | yes |
| 400 | bad request | yes |
| 401 | unauthorized | yes |
| 415 | failed — subject holds no permissions in this context | yes |
| 425 | authentication and its refresh tokens revoked by the user | yes |
| 450 | token invalid, expired, revoked or inactive | yes |
| 460 | certificate invalid, chain error, untrusted, revoked, suspended or malformed | yes |
| 470 | authorisation methods of a deceased person | yes |
| 500 | unknown error | yes |
| 550 | cancelled by the system; retry later | yes, but retryable |

Two of these collapse several distinct causes into one number: **450** covers four token
problems and **460** covers six certificate ones. The distinction arrives only in
`StatusInfo.description`, so surface the server's wording rather than a code-to-string
table of our own.

**Treat any unrecognised code as terminal.** Assuming otherwise polls a dead operation for
ever, and the docs already warn that on DEMO and PROD a legitimate 100 can persist for as
long as the certificate issuer's OCSP/CRL response takes (§4.2) — so "still 100" cannot be
distinguished from "stuck" by elapsed time alone.

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

### 6.1 Documented per-endpoint ceilings

Source: `limity/limity-api.md` (22.11.2025), retrieved 2026-08-22. Columns are
req/s · req/min · req/h. These are PROD defaults.

| Endpoint | s | min | h |
|---|---|---|---|
| `POST /sessions/online` | 10 | 30 | 120 |
| `POST /sessions/online/{ref}/invoices` | 10 | 30 | 180 |
| `POST /sessions/online/{ref}/close` | 10 | 30 | 120 |
| `POST /sessions/batch` | 10 | 20 | 60 |
| `POST /sessions/batch/{ref}/close` | 10 | 20 | 60 |
| `GET /sessions/{ref}/invoices/{invoiceRef}` | 30 | 120 | 1200 |
| `GET /sessions` | **5** | **10** | **60** |
| `GET /sessions/{ref}/invoices` | 10 | 20 | 200 |
| `GET /sessions/{ref}/invoices/failed` | 10 | 20 | 200 |
| `GET /sessions/*` (other) | 10 | 120 | 1200 |
| `POST /invoices/query/metadata` | 8 | 16 | 20 |
| `POST /invoices/exports` | 8 | 16 | 20 |
| `GET /invoices/exports/{ref}` | 10 | 60 | 600 |
| `GET /invoices/ksef/{ksefNumber}` | 8 | 16 | 64 |
| everything else | 10 | 30 | 120 |
| `POST /auth/challenge` (unauthenticated) | 60 per IP | — | — |

Three consequences for the client design:

- **`GET /sessions` is the tightest budget in the API** at 10/min. Session *polling* must
  use `GET /sessions/{ref}` or the per-invoice status endpoint (1200/h), never a list scan.
- **Batch part uploads are exempt from rate limiting entirely**, and the docs recommend
  uploading parts in parallel. Relevant for 0.2.
- The per-hour ceilings bite long before the per-second ones. `POST /invoices/exports` at
  20/h is 1 per 3 minutes sustained — retry backoff has to be sized against req/h, not
  req/s.

Environment multipliers: **TEST is 10× the PROD defaults**; **DEMO replicates PROD
exactly**. TEST can be pushed to PROD-like behaviour with
`POST /testdata/rate-limits/production`, set arbitrarily with `POST /testdata/rate-limits`,
and reset with `DELETE /testdata/rate-limits`.

Higher download limits apply **20:00–06:00**; the values are unpublished pending
production tuning.

### 6.2 Size and volume limits

Source: `limity/limity.md` (21.10.2025).

| Parameter | Default |
|---|---|
| Max invoice size, no attachment | **1 MB** |
| Max invoice size, with attachment | **3 MB** |
| Max invoices per session (online or batch) | **10 000** |

Per authenticated subject, KSeF certificate ceilings are 300 enrolments / 100 active for a
NIP identifier, and 12 / 6 for PESEL or a certificate fingerprint.

Both are adjustable on TEST via `POST /testdata/limits/context/session` and
`POST /testdata/limits/subject/certificate` (with matching `DELETE`s to restore defaults),
which makes the 1 MB invoice-size rejection path testable without constructing a real 1 MB
invoice.

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

### 6a.2 The token needs a one-time XAdES authentication — which is why XAdES is in 0.1

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

**Retired 2026-08-22.** This section used to say the interim workaround was a one-time
out-of-band mint via the official C# client. That is no longer necessary — the certificate
flow has landed, and `rake auth:bootstrap` does the whole chain in this gem. See §6a.3.

### 6a.3 `rake auth:bootstrap`

Implemented in `tasks/ksef_bootstrap.rb` — outside `lib/`, so never packaged, but covered
by `spec/tasks/ksef_bootstrap_spec.rb` against stubs rather than left as an untested
script. A checksum bug here would otherwise surface as an opaque rejection from a remote
server.

What it does, in order:

1. invents a NIP and a PESEL, both checksum-valid, the NIP also shaped to satisfy the auth
   schema's `TNIP` pattern (§4.1);
2. `POST /testdata/person` — unauthenticated, which is the only reason the chain is not
   circular;
3. generates a self-signed certificate carrying `serialNumber=PNOPL-<pesel>` (§4.4), or
   uses a real qualified certificate if one is supplied;
4. runs the full §4.2 flow: challenge → sign → submit → poll → redeem;
5. `POST /tokens` with the access token, requesting `InvoiceRead` and `InvoiceWrite`;
6. prints `KSEF_TEST_NIP` and `KSEF_TEST_TOKEN`, which are stored as **environment**
   secrets on `ksef-test` — not repository secrets. A repository secret is readable by
   every workflow in the repo, which for a live KSeF credential is more exposure than
   it needs; only a job declaring the environment can read an environment secret.

**PESEL checksum**, needed for step 1 and not previously ledgered: weights
`1,3,7,9,1,3,7,9,1,3` across the first ten digits; the eleventh is `(10 - sum % 10) % 10`.
Confirmed the way §6a.1 confirmed the NIP algorithm — it validates every PESEL the upstream
documentation ships (`15062788702`, `30112206276`, `38092277125`, `88102341294`) and
rejects those values with the check digit altered.

**PESEL is a structured identifier, and KSeF enforces it.** Learned from the API itself,
2026-08-23 — `POST /testdata/person` rejected a checksum-perfect PESEL with:

```
400 [21405] Żądanie jest nieprawidłowe. Invalid PESEL format.
```

The first six digits encode a **birth date**, with the century folded into the month field:

| Month field | Century |
|---|---|
| 01–12 | 1900s |
| 21–32 | 2000s |
| 41–52 | 2100s |
| 61–72 | 2200s |
| 81–92 | 1800s |

Confirmed by decoding every PESEL the upstream docs ship: `15062788702` → 1915-06-27,
`30112206276` → 1930-11-22, `38092277125` → 1938-09-22, `88102341294` → 1988-10-23. All
four are plain 1900s dates.

Nothing upstream *states* this. `dane-testowe-scenariusze.md` shows PESELs in examples but
never describes their structure, and the OpenAPI schema types the field as `string`. **This
is the first fact in this ledger whose source is the API's own behaviour** rather than a
document or a reference implementation — a strictly more reliable tier than anything above
it, and the only one that cannot be obtained offline.

The generator draws births from 1950–1999; the validator accepts the full scheme range,
because 1800s and 2000s PESELs are legitimate even if implausible for a test person.

**NIP checksum, stated precisely** because it is easy to get backwards: the check digit
*is* the weighted sum `mod 11`, **not** `11 - (sum mod 11)`. Confirmed against four NIPs
from the upstream docs. A sum of 10 is unrepresentable, so that draw is discarded.

The task refuses any environment whose `test_data_api?` capability is false, so DEMO is
refused as well as PROD — the `/testdata/*` endpoints exist on TEST only, and the guard is
on the capability rather than the name so a `custom` environment cannot slip past.

Tokens are minted in a `Nip` or `InternalId` context with a fixed permission set chosen at
creation — changing permissions requires a new token. For this gem's integration suite,
`InvoiceRead` and `InvoiceWrite` are the relevant ones. Treat the token as a confidential
secret (`tokeny-ksef.md` says so explicitly).

### 6a.4 Verified against live TEST, 2026-08-23

`rake auth:bootstrap` completed against the TEST environment and produced a usable KSeF
token. Because a token can only be minted with an `accessToken`, which requires a redeemed
authentication, which requires status `200`, that single outcome establishes several things
that no amount of offline testing could:

- **KSeF accepts the XAdES-BES signature this gem produces.** The combination chosen in
  §4.3 — enveloped, exclusive c14n, `rsa-sha256`, `xmlenc#sha256`, with the ETSI `Type` URI
  on the `SignedProperties` reference — is accepted in practice, not merely permitted by
  the allow-list.
- **The 2.0 namespace is correct** (§14.4). The document was sent with
  `xmlns="http://ksef.mf.gov.pl/auth/token/2.0"` and was not rejected. Whether 2.1 would
  also be accepted remains unverified; there is now no reason to find out.
- **`/testdata/person` really is unauthenticated**, as §6a.1 read from the contract.
- **A self-signed certificate is accepted on TEST** (§4.6), carrying the PESEL as
  `serialNumber=PNOPL-<pesel>` (§4.4).
- **The whole §4.2 flow works as ledgered**, including polling on `StatusInfo.code` and
  single-use redemption.

Two failures on the way there, both bugs on this side rather than upstream: a local OpenSSL
trust store with no CA bundle (see §6a.5), and the PESEL structure above.

### 6a.5 A missing CA bundle looks like a broken server certificate

Also learned the hard way, 2026-08-23. On a machine where Homebrew's `openssl@3` is
installed but `/usr/local/etc/openssl@3/cert.pem` is absent, Ruby has **no trust store at
all**, and the failure reads:

```
certificate verify failed (self-signed certificate in certificate chain)
```

which points at the wrong thing entirely. KSeF's chain is genuine —
`*.ksef.mf.gov.pl` → `GeoTrust TLS RSA CA G1` → `DigiCert Global Root G2` — and the "self-signed
certificate" being complained about is that DigiCert root, self-signed as every root is.
With no store to chain to, OpenSSL reports the last certificate it saw.

`curl` succeeds throughout, because it uses Apple's store rather than OpenSSL's, so a
reachability check proves nothing about what Ruby will do.

Fix without weakening anything: point OpenSSL at a real bundle,
`SSL_CERT_FILE=/usr/local/etc/ca-certificates/cert.pem`, or reinstall Homebrew's
`ca-certificates` to restore the symlink. **Never by disabling verification** — that is a
hard rule, and the misleading error message makes it a tempting one to break.

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

### 8.1a Rate buckets — resolves DESIGN.md §7.3 [VERIFY]

Read from the `xsd:documentation` on each element in the pinned schema, which is the only
authoritative statement of the mapping. Getting this wrong misreports VAT.

| Net | Tax | Covers | Rate codes |
|---|---|---|---|
| `P_13_1` | `P_14_1` | Standard rate ("stawka podstawowa") | `23`, `22` |
| `P_13_2` | `P_14_2` | First reduced rate | `8`, `7` |
| `P_13_3` | `P_14_3` | Second reduced rate | `5` |
| `P_13_4` | `P_14_4` | Flat rate for passenger taxis | `4` |
| `P_13_5` | `P_14_5` | Special procedure, Act ch. XII s. 6a | `3` |
| `P_13_6_1` | — | 0% excluding intra-EU supply and export | `0 KR` |
| `P_13_6_2` | — | 0% intra-EU supply of goods (WDT) | `0 WDT` |
| `P_13_6_3` | — | 0% export | `0 EX` |
| `P_13_7` | — | Exempt from tax | `zw` |
| `P_13_8` | — | Supply outside the country | `np I` / `np II` |
| `P_13_9` | — | Services under Act art. 100(1)(4) | — |
| `P_13_10` | — | Reverse charge, buyer is the taxpayer (art. 17) | `oo` |
| `P_13_11` | — | Margin scheme (art. 119, 120) | — |
| `P_15` | | **Total amount due** (gross) | |

Two things that fall out of this and matter for the builder:

- **The zero-rated and exempt buckets have no `P_14_*` counterpart.** There is no tax
  amount to report, so a summary builder must not emit a paired tax field for them —
  the schema has no element to put it in.
- **`P_14_1W`, `P_14_2W`, `P_14_3W`, `P_14_4W`** are the foreign-currency variants,
  carrying the tax amount converted per the Act when the invoice is issued in a currency
  other than PLN. They sit alongside their base field in the same sequence, so a
  non-PLN invoice populates both.

`P_15Z` and `P_15ZK` relate to advance-payment invoices and their corrections, which are
0.1 scope but not Phase 1 (DESIGN.md §7.4 puts ZAL after VAT and KOR).

### 8.2 Non-obvious mandatory elements

Discovered by validating against the schema rather than by reading it, and asserted in
`spec/ksef/fa3/validator_spec.rb`.

**`Podmiot2` (the buyer) requires both `JST` and `GV`** — `minOccurs="1"` on each, typed
`etd:TWybor1_2` so the only permitted values are `"1"` and `"2"`:

| Element | Meaning | `"1"` |
|---|---|---|
| `JST` | Buyer is a subordinate unit of a local-government body | yes |
| `GV` | Buyer is a member of a VAT group | yes |

Every invoice must therefore state these two facts about its buyer, even for an ordinary
domestic B2B sale where both answers are "no" (`"2"`). Omitting either makes the document
schema-invalid, and no prose in the integrator documentation flags it — the builder must
default them rather than leave them to the caller to discover.

Also mandatory and easy to miss, all inside `Fa/Adnotacje`: `P_16`, `P_17`, `P_18`,
`P_18A`, `P_23`, plus the three wrapper elements `Zwolnienie`, `NoweSrodkiTransportu` and
`PMarzy` — each of which is one of the four types whose root compositor is a choice
(§8.1), so exactly one branch of each must be present.

### 8.3 Import chain and offline validation

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
(DESIGN.md §0.2). Reviewed 2026-08-23.

- **Business-rule catalogue** for validation tier 3 (DESIGN.md §7.7). The only genuinely
  open blocker of the original set. `faktury/weryfikacja-faktury.md` is the next place to
  look; not yet pinned.
- **Error-code catalogue.** Still open, but **narrowed**: the eleven *authentication
  operation* status codes are now recorded at §4.8, from the reference implementation.
  What remains is the per-endpoint `ExceptionResponse` codes — `21470` (§10.2) and `21405`
  are known; the rest must be collected from the spec per operation, or observed. The C#
  client has sibling files (`CertificateStatusCodeResponse`, `InvoiceInSessionStatusCodeResponse`,
  `OperationStatusCodeResponse`, `InvoiceExportStatusCodeResponse`) that will likely close
  the corresponding areas the same way when those subsystems are built.
- **Nightly higher rate limits** (§6.1) — the 20:00–06:00 values are explicitly
  unpublished pending production tuning. Do not hard-code a nightly multiplier.
- **Whether `upo.pages[].downloadUrl` arrives absolute or host-relative** — see §14.2.
  `srodowiska.md` states only that a returned URL's *host* matches the environment called,
  so the code must resolve a relative value against that host and use an absolute one as
  is. Needs a live session to settle. (An earlier revision of this bullet said the field
  should simply be ignored; that was the superseded reading, corrected in §14.2 — the link
  is unmetered and hash-verified, so ignoring it costs something real.)

### 9.1 Resolved

Kept as a record so they are not re-investigated. The 2026-08-22 pass over the newly
pinned prose (§1.3) closed four of the five items that were open, including both that were
marked as blocking Phase 2.

| Item | Where it now lives |
|---|---|
| Challenge 10-minute validity | §4 — verified from `uwierzytelnianie.md`, no longer hearsay |
| JWT lifetime and refresh mechanics | §4.2 — access token to its `exp`, refresh token up to 7 days |
| `P_13_x` / `P_14_x` rate-bucket mapping | §8.1a — read from the XSD's own documentation |
| Base URLs for all three environments | §2 — read from each environment's own OpenAPI document |
| Error model and `Retry-After` semantics | §5 |
| XSD redistribution terms | §1.2 — MIT, so the schemas are bundled |
| TEST credential provisioning | §6a |
| **Crypto parameters** *(was: blocks all of Phase 2)* | §10 — from `sesja-interaktywna.md` and `uwierzytelnianie.md`, corroborated by both reference clients |
| **XAdES signature specifics** *(was: blocks Phase 2's first step)* | §4.3 — an allow-list, so no single shape had to be reverse-engineered |
| **Session semantics** | §11 — 12-hour lifetime, many invoices, concurrent sessions permitted |
| **UPO document format** | §12 — schema pinned to `lib/ksef/upo/schema/`, six examples to `spec/fixtures/upo/` |
| TEST bootstrap for a real credential | §4.6 — upstream ships a console app that does it |

---

## 10. Cryptography — resolves DESIGN.md §6.4 [VERIFY]

Primary source: `sesja-interaktywna.md` "Wymagania wstępne" and `uwierzytelnianie.md` §2.2
(upstream's own numbering) — **both first-tier documentation, not inferred from client
behaviour.**
Independently corroborated against `KSeF.Client/Api/Services/CryptographyService.cs`
(`ksef-client-csharp`) and `DefaultCryptographyService.java` (`ksef-client-java`), both
retrieved 2026-08-22. Where a line number is cited below it is from the C# file.

### 10.1 Parameters

| Purpose | Algorithm | Detail |
|---|---|---|
| Invoice payload | **AES-256-CBC**, **PKCS#7** padding | 256-bit key, 128-bit IV, 128-bit block (`CryptographyService.cs:486–490`) |
| Symmetric key wrapping | **RSAES-OAEP**, SHA-256 digest + **MGF1-SHA-256** | `RSAEncryptionPadding.OaepSHA256` (`:133`, `:423`) |
| KSeF token (§4.5) | **RSA-OAEP**, SHA-256 + MGF1-SHA-256 | over `{token}\|{timestampMs}` UTF-8 |
| Key and IV generation | CSPRNG | 32 and 16 bytes respectively (`:498`, `:507`) |

A fresh symmetric key per session is **recommended** by the docs, not required.

Java uses the JCE name `AES/CBC/PKCS5Padding`; for a 16-byte block PKCS#5 and PKCS#7 are
the same padding, so this is not a divergence.

Ruby equivalents: `OpenSSL::Cipher.new("aes-256-cbc")` with `#random_key` / `#random_iv`,
and `OpenSSL::PKey::RSA#public_encrypt` is **not** sufficient — OAEP with an explicit MGF1
digest needs `OpenSSL::PKey::RSA#encrypt` with
`rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256"`.

**No golden vectors exist upstream.** Neither client repository commits fixed
plaintext/ciphertext pairs; `Compatibility/CryptoCompat*.cs` are polyfills for older .NET
runtimes, not test vectors. This is acceptable: AES-256-CBC/PKCS#7 and RSA-OAEP-SHA256 are
standard primitives that OpenSSL reproduces by construction, and NIST/RFC vectors validate
them just as well as a C#-generated pair would. What is *not* standard, and therefore does
need pinning down, is the framing — see §14.1.

### 10.2 Public key distribution and rotation

Source: `bezpieczenstwo/klucze-publiczne-do-szyfrowania.md` (05.05.2026).

`GET /security/public-key-certificates` returns a list of:

| Field | Meaning |
|---|---|
| `certificate` | X.509 in **DER, Base64-encoded, without PEM BEGIN/END armour** |
| `certificateId` | SHA-256 of the DER certificate, Base64 |
| `publicKeyId` | SHA-256 of the DER `SubjectPublicKeyInfo`, Base64 — **the selector sent back to the API** |
| `validFrom`, `validTo` | validity window |
| `usage` | array; known values `KsefTokenEncryption`, `SymmetricKeyEncryption` |

Certificates are issued by a qualified CA with `CN = Ministerstwo Finansów`.

**Selection rule** (documented, so not a judgement call): pick by `usage`, require validity
at the moment of use, and where several are valid prefer **the latest `validFrom`**.

`publicKeyId` must be sent on `POST /auth/ksef-token`, `POST /sessions/online`,
`POST /sessions/batch` and `POST /invoices/exports`. It appears in the spec as
`EncryptionInfo.publicKeyId`.

Two distinct rotation modes, which the client must not conflate:

- **Re-certification** — new certificate, *same* key pair. `publicKeyId` is unchanged.
- **Key rotation** — new key pair, so `publicKeyId` changes. Planned rotations publish the
  new certificate early and both appear for the same `usage` during the overlap; emergency
  rotations revoke the old one and drop it from the list immediately.

Because emergency rotation is possible at any time, **the certificate list must not be
cached indefinitely**. The documented recovery path is specific: on **HTTP 400 with code
`21470`** ("the supplied key identifier is unknown or refers to a withdrawn key"), re-fetch
the list, re-select, and repeat the operation. This is the one case where a failed POST
should be retried after remediation — and it is remediation, not a blind retry, so it does
not conflict with the never-auto-retry-POST rule.

---

## 11. Online session semantics — resolves the §9 session item

Source: `sesja-interaktywna.md` (10.07.2025), retrieved 2026-08-22.

| Fact | Value |
|---|---|
| Session lifetime | **12 hours** from creation; `validUntil` in the open response |
| Invoices per session | many — up to the 10 000 cap of §6.2 |
| Concurrent sessions | **permitted**, multiple per authentication |
| Open cost | "lightweight and synchronous" |
| Expiry behaviour | session closes automatically at `validUntil` |

Flow: `POST /sessions/online` → `POST /sessions/online/{ref}/invoices` (repeat) →
`POST /sessions/online/{ref}/close`. Closing triggers **asynchronous** generation of the
collective UPO; it is not available at the moment `close` returns.

### 11.1 The send-invoice request carries four integrity values

`POST /sessions/online/{ref}/invoices` requires the hash **and** size of *both* the
plaintext and the encrypted document, plus the Base64 ciphertext:

- `invoiceHash` + size — SHA-256 of the **plaintext** XML
- `encryptedInvoiceHash` + size — SHA-256 of the **ciphertext**
- `encryptedInvoiceContent` — Base64 of the ciphertext

Computing either hash over the wrong artifact is an easy and silent mistake; both must be
covered by tests.

### 11.2 Session open request

`OpenOnlineSessionRequest` = `formCode` + `encryption` (pinned spec, `components.schemas`).
`formCode` is the triple `systemCode` / `schemaVersion` / `value` — for FA(3) that is
`FA (3)` / `1-0E` / `FA`, consistent with §8's finding that `KodFormularza` is `FA` and
`FA (3)` is the `kodSystemowy`. `encryption` is `EncryptionInfo` =
`encryptedSymmetricKey` + `initializationVector` + `publicKeyId`.

### 11.3 Accepted schema versions differ by environment

Source: `srodowiska.md` (16.03.2026). **TEST accepts FA(2), FA(3), FA_PEF(3) and
FA_KOR_PEF(3); DEMO and PROD accept only FA(3), FA_PEF(3) and FA_KOR_PEF(3).** FA(2) works
on TEST and is rejected in production — a trap for anyone who validates their integration
solely against TEST.

Also from the same document: test environments have a **maintenance window 16:00–18:00**
(from 2025-10-01), which the nightly integration workflow should avoid.

---

## 12. Session status and UPO

Source: `faktury/sesje/sesja-sprawdzenie-stanu-i-pobranie-upo.md` (20.04.2026).

| Operation | Endpoint |
|---|---|
| List sessions | `GET /sessions` (filter by type/status; `continuationToken`) |
| Session status | `GET /sessions/{ref}` |
| Session invoices | `GET /sessions/{ref}/invoices` |
| One invoice | `GET /sessions/{ref}/invoices/{invoiceRef}` |
| Rejected only | `GET /sessions/{ref}/invoices/failed` |
| UPO by invoice ref | `GET /sessions/{ref}/invoices/{invoiceRef}/upo` |
| UPO by KSeF number | `GET /sessions/{ref}/invoices/ksef/{ksefNumber}/upo` |
| Collective session UPO | `GET /sessions/{ref}/upo/{upoRef}` |

Session status carries `invoiceCount`, `successfulInvoiceCount`, `failedInvoiceCount`, and
**after close** a `upo.pages[]` array of `{ referenceNumber, downloadUrl }`.

- The UPO is **XML, XAdES-signed by the Ministry of Finance**, conforming to the pinned
  `upo-v4-3.xsd`. It is the legal proof of receipt: archive the bytes **verbatim**.
  Re-serialising it — even losslessly by XML rules — risks invalidating the signature.
- **A collective UPO holds at most 10 000 invoice entries**, which is why `pages[]` is an
  array. A client that reads only `pages[0]` silently loses proof of receipt for the rest.
- Paging throughout this area is `continuationToken`-based, not offset-based.
- `downloadUrl` has a path-prefix inconsistency — §14.2.

Reference numbers share a shape: `YYYYMMDD-XX-<hex>-<hex>-CC`, where `XX` is a kind tag
(`CR` challenge, `SB` batch session, `EU` UPO) and `CC` looks like the same CRC-8 checksum
as §13. Only the KSeF-number form is documented; **do not validate the others against §13's
algorithm** without verifying it first.

---

## 13. KSeF number structure — verified with a working example

Source: `faktury/numer-ksef.md`. Format, always **exactly 35 characters**:

```
9999999999-RRRRMMDD-FFFFFFFFFFFF-FF
```

Seller NIP (10) · `-` · acceptance date `YYYYMMDD` (8) · `-` · technical part (12 uppercase
hex) · `-` · CRC-8 checksum (2 uppercase hex).

CRC-8 parameters: **polynomial `0x07`, initial value `0x00`**, no reflection, no final XOR,
computed over the **first 32 characters** (everything before the final hyphen), rendered as
two uppercase hex digits.

Verified locally 2026-08-22 against the documented example — CRC-8 of
`5265877635-20250826-0100001AF629` is `0xAF`, matching the published
`5265877635-20250826-0100001AF629-AF`. This doubles as the golden vector for the
implementation.

One business fact worth surfacing in the API: per `limity/limity-api.md`, **the invoice's
official receipt date is the date its KSeF number was assigned**, not the date the client
downloaded it.

---

## 14. Contradictions within upstream's own sources

Distinct from §7, which records divergences from *our* design document. These are places
where upstream's prose, its OpenAPI contract and its reference clients disagree. Precedence
per DESIGN.md §2: the pinned artifacts win.

### 14.1 The IV is *not* prefixed to the ciphertext

`sesja-interaktywna.md` describes the 128-bit IV as "dołączanego jako prefiks do
szyfrogramu" — appended as a prefix to the ciphertext. **This is wrong for the online
session invoice path**, and following the prose produces a payload KSeF cannot decrypt.

Three sources agree against it (all 2026-08-22):

1. **The pinned OpenAPI spec** — `EncryptionInfo` carries `initializationVector` as a
   discrete field of the session-open request, alongside `encryptedSymmetricKey` and
   `publicKeyId`. Highest precedence.
2. **C#** — `EncryptBytesWithAES256` returns the encryptor's output directly, with no
   prepended bytes (`CryptographyService.cs:149–161`).
3. **Java** — `cipher.doFinal(content)`, likewise bare
   (`DefaultCryptographyService.java`).

**Resolution: send the IV once in the session-open request; the per-invoice ciphertext is
bare.** The prose's "prefix" phrasing may describe the separate ECDH/AES-GCM path, which
*does* concatenate — `subjectPublicKeyInfo || nonce || tag || ciphertext`
(`CryptographyService.cs:446`) — but that path is not used for online-session invoices.

### 14.2 `downloadUrl` is a pre-signed link, not a path to join

**Corrected 2026-08-22.** An earlier revision of this section said the field carried a
stray `/api/v2` prefix and concluded "treat `downloadUrl` as advisory and construct the
path yourself". That conclusion was drawn from the *prose example* without checking the
OpenAPI contract, which is the higher-precedence artifact and describes the field
explicitly. The conclusion was wrong, and following it would have discarded something
worth having.

`UpoPageResponse.downloadUrl` is `format: uri`, and the contract's own description says:

- the link is **generated on every status query**, so it is not a stable identifier;
- access is by `HTTP GET` and the access token **must not be sent** ("*nie należy* wysyłać
  tokenu dostępowego");
- it is **not subject to API rate limits**, and expires at `downloadUrlExpirationDate`;
- the response carries **`x-ms-meta-hash`** — the SHA-256 of the UPO document, Base64.

The `x-ms-meta-hash` header is Azure Blob Storage's, so this is a pre-signed storage URL
rather than an API route. That also explains the prefix that prompted the original
misreading: the field is not meant to be concatenated with the base URL at all, so whether
the documented example looks host-relative is beside the point.

Both reference clients implement it that way. `ksef-client-csharp` exposes two distinct
paths — `GetSessionUpoAsync(sessionRef, upoRef, accessToken)` for the metered API route,
and `GetUpoAsync(Uri)` / `GetUpoWithHashAsync(restClient, uri)` for the link, the latter
passing **`token: null`** explicitly.

**Resolution: follow `downloadUrl` as an opaque absolute URI, without the bearer token,
and verify `x-ms-meta-hash` against the bytes received.** Given how tight the session
budgets are (§6.1 — `GET /sessions` allows 10/min), an unmetered path with a built-in
integrity check is the better default; `GET /sessions/{ref}/upo/{upoRef}` remains the
fallback when the link has expired.

Two consequences for the client design. The URL must never be logged or persisted as a
durable reference — it expires, and it is credential-bearing. And the token-suppression is
not optional politeness: sending a bearer token to third-party storage leaks it.

**Unverified:** whether the live API returns this field absolute or host-relative.
`srodowiska.md` says only that a returned URL's *host* matches the environment called. Code
should therefore resolve it against the environment's base host if it arrives relative, and
use it as-is if absolute.

### 14.3 Every upstream UPO example fails upstream's own UPO schema

Measured locally 2026-08-22, with both artifacts pinned at `1c34fe27`: all **six** worked
examples under `faktury/upo/przyklady/v4-3/` fail XSD validation against
`upo-v4-3.xsd` — each with exactly one error, the same one.

`upo-v4-3.xsd:13` constrains the receiving party's name to a fixed value:

```xml
<xsd:element name="NazwaPodmiotuPrzyjmujacego" fixed="Ministerstwo Finansów">
```

while every example — all captured on TEST — carries:

```xml
<NazwaPodmiotuPrzyjmujacego>Ministerstwo Finansów - środowisko testowe (TE)</NazwaPodmiotuPrzyjmujacego>
```

Verified that this is the *only* discrepancy: with the `fixed` attribute removed, all six
validate clean. So the schema is otherwise accurate, and the examples are otherwise
well-formed UPOs.

**Consequence, and it is a real one:** the `fixed` value evidently describes PROD, while
the non-production environments append an environment marker. A client that strictly
XSD-validates a received UPO **will reject every UPO issued by TEST and, presumably,
DEMO.** Given this gem already does offline XSD validation for FA(3), that is a trap it
would otherwise have walked straight into.

**Resolution: do not hard-fail UPO validation on this element.** Either validate with the
constraint relaxed, or treat a `NazwaPodmiotuPrzyjmujacego` mismatch as a warning carrying
the observed value. Whichever is chosen, the UPO bytes are still archived verbatim (§12) —
validation is a diagnostic here, never a gate on storing legal proof of receipt.

The pinned examples double as regression fixtures for exactly this behaviour: a correct
implementation accepts all six.

Not treated as a §9 open item: the facts are measured and unambiguous. What is *not*
verified is whether DEMO uses a third spelling and whether PROD matches the `fixed` value
exactly — neither can be checked without access to those environments, and neither changes
the resolution above.

### 14.4 Both auth schemas carry broken regular expressions

Measured 2026-08-22 against the pinned `schemat_auth_v2-{0,1}.xsd`. The root cause is the
same in both: **XML Schema regular expressions are implicitly anchored, and `^` / `$` are
*literal characters*, not anchors** (XSD Part 2, Appendix F — the metacharacters are
`. \ ? * + { } ( ) [ ] |`). Patterns written as if they were Perl regexes therefore mean
something quite different from what their author intended.

#### v2.0 does not compile at all

Its three IP patterns use `\b`, which XSD regex has no concept of. libxml2 rejects the
whole file rather than just those facets:

```
FATAL: failed to compile: Wrong escape sequence, misuse of character '\'
ERROR: Element 'pattern': The value '^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$'
       of the facet 'pattern' is not a valid regular expression.
```

So `schemat_auth_v2-0.xsd` cannot be used to validate anything — you get a schema
compilation failure, not a validation result. (The same patterns also make dots optional
via `\.?`, so even parsed loosely they would match `1111`.) **Resolution: validate against
v2.1 only.** v2.1 rewrote all three patterns correctly.

#### Neither reference client validates locally, and both send 2.0

Checked 2026-08-22, and this is what settles how to respond to the defects below.

- **C#** serialises via `XmlSerializer` in `AuthenticationTokenRequestSerializer` with no
  schema attached, and writes the context value straight through
  (`writer.WriteString(Value)`).
- **Java** marshals via JAXB without ever calling `marshaller.setSchema(...)`.

So the bundled XSD is a **codegen input, not a runtime check** in both clients, and the
broken patterns below never fire for them: they emit the natural identifier and let the
server decide. Notably the Java client ships its *own* edited copy of the 2.0 schema
(`ksef-client/src/main/resources/xsd/AuthTokenRequest.xsd`) in which the IP patterns are
repaired — just loosely, `([0-9]{1,3}\.){3}[0-9]{1,3}` would admit `999.999.999.999` —
**but `TNipVatUE` and `TPeppolId` are left broken**, which is independent confirmation that
those two are genuinely defective rather than misread.

This gem does the same thing for those two types (emit the real value, treat local
validation as advisory) and additionally sends the 2.0 namespace both clients use.

#### Two of v2.1's four context identifiers cannot hold their real values

Because `^` and `$` are literal, `TPeppolId`'s pattern `^P[A-Z]{2}[0-9]{6}$` matches only
a value that literally begins with `^` and ends with `$`; and `TNipVatUE`'s pattern ends
with a stray `$`, so it demands a trailing dollar sign. Measured:

| Element | Value | Against v2.1 |
|---|---|---|
| `Nip` | `5265877635` | valid |
| `InternalId` | `5265877635-12345` | valid |
| `NipVatUe` | `5265877635-ATU12345678` — **upstream's own documented example** | **invalid** |
| `NipVatUe` | `5265877635-ATU12345678$` | valid |
| `PeppolId` | `PPL123456` | **invalid** |
| `PeppolId` | `^PPL123456$` | valid |

That upstream's own example value for `NipVatUe` fails the schema that defines it is the
clearest evidence this is an upstream defect and not a misreading.

**Resolution: emit the natural value and treat offline validation of those two context
types as advisory.** Emitting `^PPL123456$` to satisfy a broken facet would be absurd and
would certainly be rejected server-side, where the real identifier is what gets looked up.
Nothing is lost in practice: a KSeF token can only be issued in a `Nip` or `InternalId`
context anyway (§4.1), and both of those validate cleanly.

Whether the API enforces this XSD server-side is **unverified** and needs a live TEST call
to settle. If it does, `NipVatUe` and `PeppolId` authentication are simply unusable until
upstream fixes the patterns — which would be their bug to fix, not something a client can
work around.

### 14.5 A signed `AuthTokenRequest` can never be schema-valid

Measured 2026-08-22. The API **requires** an enveloped XAdES signature on this document
(§4.3: detached is rejected). The schema that defines the document declares a closed
sequence — `Challenge`, `ContextIdentifier`, `SubjectIdentifierType`, optional
`AuthorizationPolicy` — with **no `xsd:any`**. So the signature the API demands is, to the
schema, an unexpected element:

```
ERROR: Element '{http://www.w3.org/2000/09/xmldsig#}Signature': This element is not
expected. Expected is ( {http://ksef.mf.gov.pl/auth/token/2.0}AuthorizationPolicy ).
```

The same document validates cleanly before signing. This is not a defect a client can work
around — both requirements come from upstream and they contradict each other.

**Resolution: validate before signing, never after.** `Signer#sign` does this by default,
which also means a malformed document is caught before a signature is spent on it. Anyone
reaching for "validate the thing we are about to send" will find it always fails; that is
this, not a bug in the document.

Consistent with §14.4's finding that neither reference client validates locally at all —
had they tried, they would have hit this immediately.
