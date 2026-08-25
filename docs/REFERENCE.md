# Verification ledger

Every fact the implementation depends on, with its source and retrieval date, per
DESIGN.md §0 rule 2 and §2. **Nothing about endpoint paths, XML element names, namespace
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
| `faktury/weryfikacja-faktury.md` | §15 — invoice admission checks; the tier-1 specification |
| `limity/limity-api.md`, `limity/limity.md` | §6, §6.1 — rate and size limits |
| `srodowiska.md` | §2, §11.3 — environments, accepted schema versions |
| `dane-testowe-scenariusze.md` | §6a — TEST data provisioning |
| `tokeny-ksef.md` | §4.1, §6a.2, §6a.3 — KSeF token issuance, permitted contexts, confidentiality |

(The `tokeny-ksef.md` row was missing until 2026-08-23 though the file was pinned all
along. It is load-bearing: it is the sole source for "a token can only be issued in a `Nip`
or `InternalId` context", which is what restricts `Auth::Token::CONTEXT_TYPES` to two of
the contract's four.)

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

### 1.4 The FA(3) sample corpus comes from two *other* repositories

DESIGN.md §7.6 requires the parser's round-trip law to run against "Ministry-published
FA(3) sample files". **There are none in `ksef-api`** — its `faktury/` tree holds schemas,
prose and UPO examples, and not one example invoice. The samples exist, in two sibling
CIRFMF repositories, and were pinned 2026-08-24:

| Local path (under `spec/fixtures/fa3/`) | Source | Why this one |
|---|---|---|
| `ksef-pdf-generator/invoice.xml` | `CIRFMF/ksef-pdf-generator` @ `2b7c1da`, `assets/invoice.xml` | The primary sample: 13 KB, richly populated, and **the only candidate with no placeholders** |
| `ksef-client-csharp/invoice-template-fa-3.xml` | `CIRFMF/ksef-client-csharp` @ `406904d`, `KSeF.Client.Tests.Core/Templates/` | The minimal case |
| `ksef-client-csharp/invoice-template-fa-3-with-custom-Subject3.xml` | same | Carries `Podmiot3`, which our model cannot represent — the fixture that proves the parser does not silently drop it |
| `ksef-client-csharp/invoice-template-fa-3-with-disallowed-unicode-characters.xml` | same | XSD-valid and rejected by KSeF; the whole argument for tier 1 (§15.1) |

**All four validate against our pinned FA(3) schema** — measured 2026-08-24, zero errors,
**after the placeholder substitution described below**. That qualifier is not pedantry: the
three C# templates as pinned each fail on `#nip#` against `TNrNIP`, so anyone validating the
bytes on disk to check this ledger would get a non-empty error list and conclude it lies. The
pdf-generator sample needs no substitution and validates as it stands. What the result does
show is worth having: our XSD rewriting (§8.3) and our validator agree with upstream's own
test corpus.

Three practical notes:

- **The C# ones are templates, not documents.** They contain `#nip#`, `#nipOdbiorca#` and
  `#invoice_number#` placeholders, and `#nip#` is not a legal `TNrNIP`. The pinned bytes
  stay verbatim so their digests verify; substitution happens in the spec helper, which
  keeps the two concerns apart. The pdf-generator sample needs no substitution.
- **They are test-only, so §1.2's first question settles the location**: `spec/fixtures/`,
  never `lib/`, and the gemspec's `docs/*.md` + `lib/**` file list does not package them.
- **Licences differ, and one differs in substance.** `ksef-client-csharp` is MIT
  © 2025 Ministerstwo Finansów; `ksef-pdf-generator` is MIT © 2025 **CIRF** — a different
  copyright holder from every other artifact here. Both texts are retained beside the
  fixtures as `LICENSE.ksef-client-csharp.txt` and `LICENSE.ksef-pdf-generator.txt`, as MIT
  requires of a redistributor. Neither is in the digest manifest: a licence changing is a
  legal event, not a changed fact about KSeF, and it should not read as an upstream
  data change.

Being outside `ksef-api`, these four are **not** covered by §1's single-commit pin. Each row
above carries its own repository and commit.

**What a `verify:artifacts` failure actually means, here and everywhere:** the *local file
changed*. The task compares bytes on disk against recorded digests and never contacts
upstream, so an upstream repository moving is invisible to it — checking that is a manual job
against the commits recorded above. §1's "treat a mismatch as an upstream change" describes
the usual *cause* (someone re-downloaded), not the mechanism.

One practical note for a re-verifier: upstream's licence file in `ksef-client-csharp` is
`LICENCE.txt`, with the British spelling. There is no `LICENSE`, and a fetch of that name
404s.

### 1.5 The Ministry's own worked examples — and the first artifact from outside CIRFMF

Pinned 2026-08-24 to `spec/fixtures/fa3/mf-samples/`. **Twenty-six FA(3) invoices covering all
seven `RodzajFaktury` values** — 12 `VAT`, 5 `KOR`, 3 `KOR_ZAL`, 2 `ROZ`, 2 `UPR`, 1 `KOR_ROZ`,
1 `ZAL` — plus a five-page descriptions PDF that is *not* redistributed.

| | |
|---|---|
| Package | *Przykładowe pliki dla struktury logicznej e-Faktury FA(3)* |
| URL | `https://ksef.podatki.gov.pl/media/e5cia0ey/przykladowe-pliki-dla-struktury-logicznej-e-faktury-fa-3.zip` |
| Archive SHA-256 | `41ebd3c57144951c65d68a36fbe433285b5791a86a8bd46cb059503e3f8b1e10` (200 512 bytes) |
| Retrieved | 2026-08-24 |

**This is the only corpus of non-`VAT` invoice types that exists.** Two independent sweeps of
every CIRFMF repository — all branches, the whole history of all six — found every FA(3) fixture
to be `RodzajFaktury=VAT`. The two files named "pef-correction" are UBL 2.1 `CreditNote`
documents, not FA(3) corrections. So DESIGN.md §7.4's remaining six types had no worked example
anywhere until this package was found, by following an issue in `CIRFMF/ksef-schematy` to the
Ministry's downloads page.

All twenty-six validate against the pinned FA(3) XSD with **zero errors** (measured 2026-08-24),
which is a second independent confirmation that §8.3's in-memory import rewriting is sound.

**They earned their keep the same day, and kept doing so.** `KOR` was built against the five
corrections here and nothing else — no upstream code models an FA(3) correction — and four of the five parse,
re-serialise and validate. Every structural decision in §8.4 was taken by reading them, and two
were taken *against* what the schema documentation alone would have suggested: Przykład 2 gives
a before/after pair the same `NrWierszaFa` where the annotation says *"z odrębną numeracją"*,
and three of the five make it plain that a correction's summary cannot be derived from its rows.
§8.4a is a third finding they produced: their KSeF numbers do not satisfy §13's checksum. `ZAL`
and `ROZ` followed on 2026-08-25 (§8.5) and the last three types on 2026-08-26 (§8.6), each
built the same way. **Twenty-two of the twenty-six now parse, re-serialise, validate and
round-trip**; the four that do not are refused for a construct — two priced gross, two
identifying their buyer by something other than a NIP — rather than for their type.

#### The licence position, and the decision taken

**This is the first artifact pinned from outside the CIRFMF GitHub organisation, and §1.2's MIT
reasoning does not reach it.** That grant arrives through the repositories; these files are in
none of them.

`podatki.gov.pl` states site-wide that using its content *"niezależnie od celu i sposobu
korzystania, nie wymaga zgody Ministerstwa Finansów"* — regardless of purpose or manner, requires
no consent from the Ministry — with CC BY 3.0 PL for material marked as copyright. **But the files
are hosted on `ksef.podatki.gov.pl`**, a subdomain carrying no licence statement of its own, and
they bear no internal notice. Whether the parent statement reaches the subdomain is an
interpretive question nobody has answered in writing.

**Decision (human, 2026-08-24, DESIGN.md §12): redistribute the twenty-six XML files as test
fixtures, with attribution.** `spec/fixtures/fa3/mf-samples/NOTICE.md` carries the source, the
retrieval date, the archive checksum, the licence statement in Polish and English, and the caveat
above stated plainly. The descriptions PDF is *not* redistributed — it is referenced by URL and
checksum only, which needs no licence at all. Nothing here is packaged: the gemspec ships
`lib/**` and `docs/*.md`, and a built gem contains **zero fixtures** — the property that
matters here. (An earlier revision also gave a file count; it has moved since and is not worth
pinning.)

Filenames were normalised to `przyklad-01.xml` … `przyklad-26.xml`. Upstream's carry Polish
diacritics and an inconsistent `FA_3_`/`Fa_3_` prefix, which travel badly across case-insensitive
filesystems and Windows checkouts; the **bytes are untouched**, and the bytes are what
`docs/artifacts.sha256` pins. `NOTICE.md` holds the full mapping.

#### What the corpus establishes, beyond being a corpus

- **`Σ P_13_* + Σ P_14_* == P_15` holds exactly in 24 of the 26** — including every correction.
  The two exceptions are the useful part, and they constrain any future tier 3: **Przykład 1 is
  off by 0.01** — bucket-level tax rounding loses a grosz (1666.66 + 383.33 + 0.95 + 0.05 =
  2050.99 against a stated `P_15` of 2051). An earlier revision called it "a gross-priced
  invoice"; it is not, and could not be, since it states `P_9A`/`P_11` throughout and the
  parser refuses gross rows while Przykład 1 is in `MINISTRY_MODELLED` (corrected 2026-08-26).
  And
  **Przykład 16 (`UPR`) omits the buckets entirely**, the descriptions PDF stating that a
  simplified invoice may carry `P_15` alone. **A zero-tolerance equality check would reject the
  Ministry's own first example**, so that rule needs a one-grosz tolerance and a
  bucket-presence guard — see §15.6.
- **A `KOR` carries deltas in the buckets**, confirming the XSD annotations: Przykład 2 uses
  before/after rows (`StanPrzed=1` on the before row, same `NrWierszaFa`) with header
  `P_13_1=-162.60`, `P_14_1=-37.40`, `P_15=-200`, reconciling exactly. Amounts are unpadded
  (`P_15=2051`, `P_15=-200`), so any comparison must be numeric and never on strings.
- **Four of the twelve `VAT` samples are beyond this model**, which is a measured map of 0.1's
  limits rather than a guess: `08` and `19` price rows **gross** (`P_9B`/`P_11A` under art. 106e
  ust. 7-8) where the model carries net pricing only, and `22`/`23` identify the buyer by
  `NrVatUE` and by `NrID` (§8.2a). Each is refused with a message naming the construct and saying
  the document is fine; `spec/ksef/fa3/round_trip_spec.rb` asserts every one, and asserts that no
  `VAT` sample is left unclassified.

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
`/auth/token/refresh` renews. This confirms the [VERIFY] in DESIGN.md §6.3's shared
epilogue — the API does issue a refresh token alongside the access token. (That section's
numbered lists stop at 3; there is no step 4 to cite.)

| Token | Lifetime | Notes |
|---|---|---|
| `accessToken` | short (docs say "kilkanaście minut"). **Read expiry from the response's `validUntil`, not the JWT `exp`** — the contract's `TokenInfo` requires `token` + `validUntil` precisely so no decoding is needed, and DESIGN.md §4.3 excludes the `jwt` dependency | sent as `Authorization: Bearer` |
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

Corroborated by the pinned contract (checked 2026-08-23): the `POST /auth/ksef-token`
operation description names **RSA-OAEP with SHA-256**, the `token|timestamp` framing, and
the timestamp "jako liczba milisekund od 1 stycznia 1970 roku". So the encryption of this
payload is stated by the contract as well as by the prose, and both are asserted in
`spec/openapi_contract_spec.rb`.

`InitTokenAuthenticationRequest` requires `challenge`, `contextIdentifier` and
`encryptedToken`; `publicKeyId` and `authorizationPolicy` are optional. **Send
`publicKeyId` anyway** — see §10.3. The `authorizationPolicy` here carries the same three
IP lists as the XAdES document's, JSON-cased (`ip4Addresses`, `ip4Ranges`, `ip4Masks`) and
capped at ten entries each, which independently corroborates §4.1's cap.

The 400 table for this operation names **`21111`** — "Nieprawidłowe wyzwanie autoryzacyjne",
an invalid authorisation challenge — alongside `21470` (§10.2) and `21405`. That is the
cheapest of the three to avoid, so the challenge format of §4.1 is checked locally before
the request is built.

`ECDsa` exists as an alternative encryption method in both reference clients. Out of scope
for 0.1; RSA is the documented default.

### 4.6 TEST bootstrap — resolves DESIGN.md §12 item 4's central unknown

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

**`authenticationMethod` is deprecated** (noted 2026-08-23). The contract marks
`AuthenticationOperationStatusResponse.authenticationMethod` `deprecated: true` and adds
`authenticationMethodInfo` (`category` / `code` / `displayName`) beside it; both are
required, so nothing breaks today. `Ksef::Auth::OperationStatus` still reads the deprecated
field. Migrating is not urgent — the value is informational and this gem never branches on
it — but it should happen before upstream removes the field, and the successor is the one
to read for new work.


### 4.8 Authentication status codes

`GET /auth/{referenceNumber}` returns **HTTP 200** carrying a `StatusInfo` whose `code` is
*not* an HTTP status — it describes the asynchronous operation. The Ministry's *prose* names
only "in progress" and "succeeded", and says the full list "will be available in the
endpoint's technical documentation".

**Source: the pinned OpenAPI contract** —
`components.schemas.AuthenticationOperationStatusResponse.properties.status.description`
carries the complete table. Re-sourced 2026-08-23, and the correction matters twice over.

An earlier revision of this section cited
`KSeF.Client.Core/Models/ApiResponses/AuthenticationStatusCodeResponse.cs` in
`ksef-client-csharp` and said this was "a reference-implementation constant, not something
the contract states". That was wrong, and it **understated our own confidence**: the prose
saying the list is not yet documented was taken at its word, and nobody looked in the
contract, which is a *first-tier* artifact. Reading it changed the table in three ways —
so the lesson generalises: when upstream prose says a fact is undocumented, check the
OpenAPI descriptions before reaching for a reference implementation.

| Code | Meaning | Terminal? |
|---|---|---|
| 100 | authentication in progress | no — the only code that means keep polling |
| 200 | succeeded | yes |
| 415 | failed — subject holds no permissions in this context | yes |
| 425 | authentication and its refresh tokens revoked by the user | yes |
| 450 | token problem — eight distinct causes, see below | yes |
| 460 | certificate invalid, chain error, untrusted, revoked, suspended or malformed | yes |
| 470 | authorisation methods of a deceased person | yes |
| **480** | **authentication blocked — suspected security incident** | yes, and **not** retryable |
| 500 | unknown error | yes |
| 550 | cancelled by the system; retry later | yes, but retryable |

The three corrections:

1. **`480` exists and was missing entirely.** "Uwierzytelnienie zablokowane — podejrzenie
   incydentu bezpieczeństwa. Skontaktuj się z Ministerstwem Finansów." It is absent from the
   C# enum, which is why it was absent here and from `Ksef::Auth::Status` until 2026-08-23.
   It is the one code whose correct response is neither a retry nor a fix on the client side:
   the user must contact the Ministry. Retrying it is the worst available move, given §6
   records that repeated suspicious behaviour lengthens a block.
2. **`450` collapses eight causes, not four** — a malformed, mistimed, revoked or inactive
   token, *plus* a bad authorisation challenge, bad token encryption, bad token encoding, and
   a token not usable in the requested context. `460` collapses six certificate ones. The
   distinction arrives only in `StatusInfo.description`, so surface the server's wording
   rather than a code-to-string table of our own.
3. **`400` and `401` are not contract codes.** They appear in the C# enum only. Kept as named
   constants because the server may still send them, but their absence from the contract is
   upstream's choice, not an omission here.

Asserted against the contract in `spec/openapi_contract_spec.rb`, so this provenance cannot
regress silently a second time.

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
| `POST /auth/ksef-token` | 60 | — | — |
| `GET /security/public-key-certificates` | 60 | — | — |

The last two are read from each operation's own `x-rate-limits` in the pinned spec
(2026-08-23) rather than from `limity-api.md`, which lists neither. Both sit well above the
"everything else" default, which is consistent with their being on the pre-authentication
path — but it also means the per-endpoint values in the spec, not just the prose table,
are the authority.

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

## 6a. Provisioning TEST credentials (DESIGN.md §12 item 4)

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
six are checksum-valid, which independently confirms **DESIGN.md** §7.2's NIP algorithm.
(Named explicitly: inside this document a bare "§7.2" would read as §7's second item.)

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
   it needs; only a job declaring the environment can read an environment secret. The
   environment is also restricted to the `main` branch, so a pushed branch cannot
   claim it and read the token.

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
- **The §4.2 steps the bootstrap exercises work as ledgered** — challenge, submission,
  polling on `StatusInfo.code`, and single-use redemption. Scoped deliberately (corrected
  2026-08-23): `POST /auth/token/refresh` is *not* among them, so nothing here vouches for
  refresh, and `POST /auth/ksef-token` did not exist at the time.

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

### 6a.6 `/testdata/person` grants permissions asynchronously

Learned from the API, 2026-08-23 — the second fact in this ledger whose source is
observed behaviour rather than a document. `POST /testdata/person` returns **200**, but the
Owner grant it describes is **not yet in effect**. Authenticating immediately afterwards
fails with status **415**, "Brak przypisanych uprawnień" (no assigned permissions), returned
on the *first* poll rather than after a `100`.

Measured, with a fresh NIP and PESEL each time:

| Wait after registering | Result |
|---|---|
| none, isolated call after an idle period | success |
| none, three calls in quick succession | success, **415**, **415** |
| ten seconds, three calls in quick succession | success, success, success |

So it is not a fixed latency but a queue: an isolated grant lands within the ~2 s the auth
flow takes, and consecutive ones do not. That is why a single manual `rake auth:bootstrap`
worked first time while a three-example integration suite failed every example.

**415 is genuinely ambiguous here**, which is the important part. It is both "the grant has
not landed yet" and the legitimate permanent answer for a subject with no rights. So:

- the **integration suite** may retry it, and does, because it provisioned the identity
  moments earlier and knows which meaning applies;
- **library code must never retry a 415.** There it is a final answer, and retrying would
  hammer the API over a permissions problem no retry can fix.

The suite now provisions **one** identity per run and settles for ten seconds, rather than
one per example — fewer test people in a shared environment, and one wait instead of three.


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

Read from the pinned schema — but from **two** places in it, and one column is weaker than
the others, which is worth stating because it is how two bugs survived here.

The `P_13_*`/`P_14_*` annotations give the **Covers** column, and they name percentages only
for buckets 1–3; they name **no rate code anywhere**. The **Rate codes** column is therefore
matched from the other side, against `TStawkaPodatku`'s own enumeration annotations — a
different part of the schema, and the part that was not re-read when this table was first
written. Where both sides name the same statutory article the match is exact and first-tier
(that is how `np I`/`np II` are settled below). Where neither does — `4` and `3` sharing
bucket 4 — the only evidence is `ksef-pdf-generator`'s UI labels *"4% lub 3%"* and *"OSS"*,
and **that file is not pinned in this repository** (§1.4 pins only that repo's
`assets/invoice.xml`). Treat that one row as second-tier. Getting this wrong misreports VAT.

| Net | Tax | Covers | Rate codes |
|---|---|---|---|
| `P_13_1` | `P_14_1` | Standard rate ("stawka podstawowa") | `23`, `22` |
| `P_13_2` | `P_14_2` | First reduced rate | `8`, `7` |
| `P_13_3` | `P_14_3` | Second reduced rate | `5` |
| `P_13_4` | `P_14_4` | Flat rate for passenger taxis | `4`, `3` |
| `P_13_5` | `P_14_5` | Special procedure, Act ch. XII s. 6a | — (see below) |
| `P_13_6_1` | — | 0% excluding intra-EU supply and export | `0 KR` |
| `P_13_6_2` | — | 0% intra-EU supply of goods (WDT) | `0 WDT` |
| `P_13_6_3` | — | 0% export | `0 EX` |
| `P_13_7` | — | Exempt from tax | `zw` |
| `P_13_8` | — | Supply outside the country, **excluding** what `P_13_5` and `P_13_9` take | `np I` |
| `P_13_9` | — | Services under Act art. 100(1)(4) | `np II` |
| `P_13_10` | — | Reverse charge, buyer is the taxpayer (art. 17) | `oo` |
| `P_13_11` | — | Margin scheme (art. 119, 120) | — (see below) |
| `P_15` | | **Total amount due** (gross) | |

Four things that fall out of this and matter for the builder:

- **The zero-rated and exempt buckets have no `P_14_*` counterpart.** There is no tax
  amount to report, so a summary builder must not emit a paired tax field for them —
  the schema has no element to put it in.
- **`np I` and `np II` are different buckets, and the schema says so twice.** `np II` is
  *"niepodlegajace opodatkowaniu na terytorium kraju, świadczenie usług o których mowa w art.
  100 ust. 1 pkt 4 ustawy"*, and `P_13_9` is *"Suma wartości świadczenia usług, o których mowa
  w art. 100 ust. 1 pkt 4 ustawy"* — the same statutory scope, word for word. Meanwhile
  `P_13_8` reads *"z wyłączeniem kwot wykazanych w polach P_13_5 i **P_13_9**"*, and `np I`
  excludes those same transactions, so `P_13_8` is the one bucket `np II` may not go in.
  **Until 2026-08-26 both codes mapped to `P_13_8`**, misstating intra-EU services on an
  XSD-valid document that tier 1 passed. Found by audit. No corpus witness exists — no `np`
  code appears in any pinned sample — so the schema's own annotations are the whole evidence,
  and they are decisive. **Third instance of this class**, after the shared-bucket
  accumulation bug and rate code `3`.

- **Bucket 4 takes rate codes `4` *and* `3`; buckets 5 and 11 take none.** Each rate bucket
  pairs a current rate with the one it replaced — 23/22, 8/7, 4/3 — and bucket 5 is not a rate
  bucket at all: `P_13_5` is the special procedure of *"dziale XII w rozdziale 6a"* and
  `P_14_5` is **"kwota podatku od wartości dodanej"**, foreign VAT under OSS, whose per-line
  rate lives in `P_12_XII` (a percentage) rather than in `P_12`. `P_13_11` is unreachable for
  its own reason: the margin scheme is declared through `Adnotacje/PMarzy`, not a rate.
  **Until 2026-08-24 this table mapped code `3` to bucket 5**, so a domestic 3% sale was
  declared as OSS foreign VAT on an XSD-valid document. Found by comparing against
  `ksef-pdf-generator`, whose summary labels read *"4% lub 3%"* for bucket 4 and *"OSS"* for
  bucket 5 — the only official code that renders these buckets. **That table row was itself
  left uncorrected until 2026-08-26**, two commits after the code was fixed, so a reader
  trusting the table over this bullet would have reintroduced the bug.
  `VatRate.unreachable_elements` names buckets 5 and 11, and a spec now asserts every *other*
  net bucket is reachable — an incomplete list there is what let `P_13_9` look like a
  deliberate gap.
- **The mapping is many-to-one, so summaries must *accumulate*.** `"23"` and `"22"` both
  report into `P_13_1`/`P_14_1`, `"8"` and `"7"` into bucket 2, `"4"` and `"3"` into
  `P_13_4`/`P_14_4`. Assigning per rate code rather than summing lets the last code win — which is
  exactly the bug found on 2026-08-24: an invoice with a 23% line of 100 and a 22% line of 200
  emitted `P_13_1=200.00` and `P_14_1=44.00` while `P_15` still carried the correct `367.00`.
  The tax base was understated by a third, `P_13_1 + P_14_1 ≠ P_15`, and **the document was
  XSD-valid** — the schema cannot see an arithmetic inconsistency, which is precisely the
  reconciliation class that validator tier 3 exists for (§15.6). Historical rates like 22%
  make this reachable on real invoices, not just in theory.
- **`P_14_1W`, `P_14_2W`, `P_14_3W`, `P_14_4W`** are the foreign-currency variants,
  carrying the tax amount converted per the Act when the invoice is issued in a currency
  other than PLN. They sit alongside their base field in the same sequence, so a
  non-PLN invoice populates both.

`P_15Z` and `P_15ZK` relate to advance-payment invoices and their corrections, which are
0.1 scope but not Phase 1 (DESIGN.md §7.4 puts ZAL after VAT and KOR).

### 8.2 Non-obvious mandatory elements

Discovered by validating against the schema rather than by reading it. `JST`/`GV` are asserted
in `spec/ksef/fa3/validator_spec.rb`; the `Adnotacje` list is enforced by
`Ksef::FA3::Invoice::DEFAULT_ANNOTATIONS` and by tier 1's key check rather than by an assertion
of its own.

**`Podmiot2` (the buyer) requires both `JST` and `GV`** — `minOccurs="1"` on each, and typed
by an **anonymous inline restriction of `xsd:integer`** enumerating `1` and `2`, so those are
the only permitted values. (Not `etd:TWybor1_2`, as an earlier revision of this line said: the
schema does use that type for `P_16`–`P_23`, but not here, and the generated metadata records
`base: "xsd:integer"` for both. Corrected by audit 2026-08-26.)

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

### 8.2a The two subjects are not symmetric, and the buyer's name is optional

Read straight from the schema while writing the parser (2026-08-24), because upstream's own
corpus contains a document that only makes sense if this is true.

`TPodmiot1` — the seller's identity — is a plain sequence of two mandatory elements:

```
NIP, Nazwa
```

`TPodmiot2` — the buyer's — is a **four-way choice** followed by an *optional* name:

```
choice( NIP | (KodUE, NrVatUE) | ([KodKraju], NrID) | BrakID )
sequence minOccurs="0" ( Nazwa )
```

Three consequences, and each one bit:

- **A buyer may have no `Nazwa` at all.** `invoice-template-fa-3-with-disallowed-unicode-characters.xml`
  has exactly that, and a parser that treats the name as mandatory rejects a document
  upstream ships as valid. `Ksef::FA3::Subject` therefore allows a nil name, and refuses one
  only for a seller — enforced in `#to_fa3`, which is the only place that knows the role.
- **An absent name must be omitted, not written empty.** `Nazwa` is `TZnakowy512`, so
  `<Nazwa/>` fails its minimum length: emitting an empty element would turn a legal buyer
  into an invalid document.
- **A buyer need not have a NIP.** `NrVatUE` covers an EU counterparty, `NrID` a
  non-EU one, and `BrakID` an unidentified buyer. This model carries a NIP only, so the
  parser reports the other three as a **limitation of the model** rather than as a malformed
  document — the distinction matters, because the invoice is fine and it is us who cannot
  hold it.

### 8.2b FA(3) has no structured address, and neither does this model

`TAdres` is `KodKraju` + `AdresL1` + optional `AdresL2` + optional `GLN`, where both address
lines are free text of up to 512 characters. There is no street, no city, no postal code.

**Checked against the only official code that reads an FA(3) address**, per CLAUDE.md's
Workflow rule ("Unsure how KSeF behaves? Read the official C#/Java clients before guessing"): `ksef-pdf-generator`'s `src/lib-public/generators/FA3/Adres.ts`
renders exactly `AdresL1`, `AdresL2`, `KodKraju` and `GLN` — nothing else exists to render.
Neither the C# nor the Java client models FA(3) at all; both take the document as bytes. So
the flat shape is upstream's, not a simplification of it.

`Ksef::FA3::Address` still *accepts* `street:`, `city:` and `postal_code:`, because that is
how an address arrives from a human or an ERP. It does not **retain** them: they compose into
`line1` at construction and the parts are gone. That is a deliberate rule, and it now applies
to three types:

| Type | Stores | Not stored |
|---|---|---|
| `Address` | `line1`, `line2`, `country` | `street`, `city`, `postal_code` — composed on the way in |
| `Line` | `BigDecimal`, rounded to its element's scale | the `Integer`/`String`/finer value it arrived as |
| `Invoice` | `issued_at` as the document's own string | the `Time` it may have been given |
| `Invoice` | `issue_date` as a `Date` | the `String` it may have been given |
| `Invoice` | `annotations` as the document states them | nothing — they used to be discarded entirely |

The `Line` and `issue_date` rows were added on 2026-08-24, after a review found the rule
stated but not followed: `issue_date` kept whatever the caller passed, and `Line` canonicalised
the *type* but not the *value*, holding `150.125` where the document will carry `150.13`
(`TKwotowy` is `fractionDigits="2"`; `TIlosci` is `6`). Both broke the round-trip law for a
field whose value never really changed, and the `Line` one also made a line's own arithmetic
disagree with the invoice as printed — a net derived from a price finer than the one shown.

**The rule: the model stores the document's representation, not the caller's input.** Two
things fall out of it. A `Float` or a malformed address is refused at construction, where the
caller can see what it passed, instead of at serialisation. And an invoice built from
structured parts is genuinely `==` to the same invoice parsed back from XML — which is what
lets DESIGN.md §7.6's round-trip law be stated as an equality rather than as a vaguer
"equivalence". Retaining the inputs would invent distinctions FA(3), KSeF and every reader of
the invoice are all blind to.

`GLN` is not carried. It is optional, nothing needs it yet, and a parsed document that has
one reports it through `Invoice#unmapped_elements` rather than losing it silently.

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

### 8.4 The correction, `KOR` — read from the XSD and measured against the Ministry's five

Source: the pinned FA(3) XSD for the structure, and the five `KOR` samples of §1.5 for what
a real one looks like. Recorded 2026-08-24, when `KOR` was built.

The correction elements are an **anonymous `<xsd:sequence minOccurs="0">`** sitting between
`RodzajFaktury` and `ZaliczkaCzesciowa` in `Fa`:

| Element | Occurs | Carried as |
|---|---|---|
| `PrzyczynaKorekty` | 0–1, `TZnakowy` | `Correction#reason` |
| `TypKorekty` | 0–1, `TTypKorekty` (1/2/3) | `Correction#effect` |
| `DaneFaKorygowanej` | **1–50 000** | `Correction#corrected` |
| `OkresFaKorygowanej` | 0–1, `TZnakowy` | `Correction#period` |
| `NrFaKorygowany` | 0–1, `TZnakowy` | `Correction#corrected_number` |
| `Podmiot1K` | 0–1 | `Correction#previous_seller` |
| `Podmiot2K` | 0–101 | `Correction#previous_buyers` |
| `P_15ZK` | 0–1, `TKwotowy` | `Correction#paid_before` — scoped to `KOR_ZAL`/`KOR_ROZ`, and it means a different thing on each; see §8.6 |
| `KursWalutyZK` | 0–1, `TIlosci` | `Correction#exchange_rate_before`; sits in the nested sequence `P_15ZK` opens, so the schema takes neither without the other |

Four consequences that are easy to get wrong:

**The group is optional; `DaneFaKorygowanej` is not optional within it.** So a `KOR` with no
correction elements at all is schema-valid, while one carrying `PrzyczynaKorekty` and nothing
else is not. `Correction` refuses the latter at construction and the parser reads the former
as simply having no correction — inventing one would change the document.

**`DaneFaKorygowanej` ends in a choice**, not two optional fields: either `NrKSeF` +
`NrKSeFFaKorygowanej`, or `NrKSeFN` alone — *"znacznik faktury korygowanej wystawionej poza
KSeF"*. The two *markers* — `NrKSeF` and `NrKSeFN` — are `etd:TWybor1`, which has exactly one
member, `"1"`: they are present or absent, with no "no" to write. (The first branch is a
sequence of the marker plus `NrKSeFFaKorygowanej`, which is a `TNumerKSeF`.) Modelled as one nil-able `ksef_number`, so
emitting both branches or neither is unrepresentable.

**`IDNabywcy` is the link between `Podmiot2K` and the `Podmiot2` it corrects** — *"unikalny
klucz powiązania danych nabywcy na fakturach korygujących"*. Both sides carry it, a correction
may name up to 101 previous buyers, and nothing else pairs them. It is therefore a field of
`Subject`, not an element to lose. `Podmiot2K` has **no `JST`/`GV`**; `Podmiot1K` makes `Adres`
mandatory as `Podmiot1` does.

**`StanPrzed` marks a row as the state before correction** — *"w przypadku gdy korekta …
jest dokonywana w sposób polegający na wykazaniu danych przed korektą i po korekcie jako
osobnych wierszy"*. Przykład 2 gives such a pair **the same `NrWierszaFa`** despite the same
sentence saying *"z odrębną numeracją"*, and pairs them by `UU_ID` too. Since `UU_ID` is not
modelled, the shared row number is the only link left, so `Line#row_number` carries it — but
only when it differs from the row's position, or a parsed ordinary invoice would stop equalling
the built invoice it came from (DESIGN.md §7.6).

#### A correction's summaries are read, never computed

This is the substantive modelling decision. An ordinary `VAT` invoice's `P_13_*`/`P_14_*` are a
function of its rows. A `KOR`'s are **deltas**, and FA(3) does not require its rows to determine
them. Measured over the five samples:

| Sample | Rows | How the summary relates to them |
|---|---|---|
| Przykład 2 | before/after pair | after − before = the stated delta |
| Przykład 3 | one row, already a delta | equals the stated delta |
| Przykład 5 | **none** | `P_15` = 0, no buckets; a pure `Podmiot2K` data correction |
| Przykład 6 | **none** | six corrected invoices, a period, buckets stated outright |
| Przykład 7 | one row with **no amounts at all** | `P_7`, `CN`, unit and quantity only |

So three of the five cannot derive a summary from their rows at any price. `Invoice#totals`
holds what the document states, and the parser fills it for every `KOR`. `Ksef::FA3::Totals`
is keyed by **element name**, not rate code, because that mapping is not invertible — `"23"`
and `"22"` share `P_13_1` (§8.1a) — and because it is the document's own representation
(§8.2b). `Invoice#lines` may then be empty, which the constructor permits **only** when totals
are stated.

The after − before rule that Przykład 2 satisfies is **deliberately not implemented**. One
witness is not a rule, no first-tier source states it, and deriving a correction's tax base
from an inference is the kind of thing §15.6 warns against. Callers state the delta.

#### The one cross-field rule tier 1 carries

**The XSD states this outright.** The anonymous sequence carries its own annotation:

> Dane dla przypadków, gdy pole RodzajFaktury przyjmuje wartości KOR, KOR_ZAL lub KOR_ROZ

— *data for the cases where the RodzajFaktury field takes the values KOR, KOR_ZAL or
KOR_ROZ*. So the rule is a first-tier fact, not an inference from `PrzyczynaKorekty`'s
*"dla faktur korygujących"*, as an earlier revision of this section said.

What the XSD **cannot do is enforce it**: the group sits in the same sequence whatever the
type, so a `VAT` invoice carrying `DaneFaKorygowanej` validates clean (measured, by injecting
the group into Przykład 1). That gap is exactly what tier 1 is for, and `ModelValidator`
reports it. **The converse is not checked** — a `KOR` without the group is schema-valid, and
complaining would be inventing a rule.

#### 8.4a The Ministry's KSeF numbers do not satisfy §13's checksum

Measured 2026-08-24: **all six distinct `NrKSeFFaKorygowanej` values in the five `KOR` samples
fail the CRC-8 of §13**. The commonest, `9999999999-20230908-8BEF280C8D35-4D`, appears in
**eleven of the twenty-six samples** — every `KOR`, every `KOR_ZAL`, the `KOR_ROZ` and both
`ROZ`. It is the **only** KSeF-number reference in eight of those eleven; przyklad-06, -07 and
-18 carry others alongside it. (Two earlier revisions were wrong here — first "three samples",
then "the sole reference in three of them", which counted only the `KOR` samples where it
stands alone. Corrected by audit 2026-08-26.) All six
match `TNumerKSeF`'s pattern — every sample is XSD-valid — so they are well-formed
placeholders rather than numbers KSeF ever issued.

Our CRC-8 is not the thing that is wrong: it reproduces the documented example of §13, and
agreed with a real number assigned on live TEST (recorded in DESIGN.md §11's run record for
`32692339217`, asserted by `spec/integration/session_flow_spec.rb`). So **tier 1 does not
check the checksum of a referenced KSeF number.** Nothing upstream says KSeF verifies it, and
rejecting on it would make tier 1 refuse the Ministry's own documents — the same failure as
the whitespace-collapse bug, whose record is the header comment of
`lib/ksef/fa3/field_checks.rb`. Do not add it.

#### 8.4b The five-lens audit of `KOR`, and the three facts it settled

Run 2026-08-24 against the merged commit, five independent read-only lenses. Three of the five
found the same top defect without conferring, which is worth recording as much as the defect
is: **a rule enforced on one side of a boundary is not enforced.**

**The derived summary.** §8.4 says a correction's summaries are *read, never computed*. That
was true of {Parser} and false of the serializer: `DocumentMapping#summary` fell back to the
line-derived buckets whenever no `Totals` was given, and nothing required a *built* correction
to give one. Since a `StanPrzed` row is the position **as it was before the correction** — an
amount already invoiced on the original document — summing it counts it twice with the wrong
sign. The Ministry's Przykład 2, built through this gem's own DSL without `f.totals`, declared
`P_15 = 3799.98` for a correction whose value is `-200.00`: a refund emitted as a charge,
XSD-valid, tier 1 silent, `#unmapped_elements` empty. Tier 1a now requires stated totals
whenever a line carries `state_before` — scoped to the marker rather than to the type, because
a correction whose rows already *are* the deltas computes correctly and Przykład 3 is exactly
that shape.

**`Integer()` honours radix prefixes.** `NrWierszaFa` is `TNaturalny`, whose lexical space
permits leading zeros, and fixed-width row numbering is an ordinary ERP convention. `Integer`
without an explicit base reads `"010"` as **octal eight**, so a schema-valid document stating
row ten parsed as row eight and re-serialised as `8` — in the one field that pairs a
correction's before/after rows once `UU_ID` is dropped. `"08"` failed the other way, raising
on a document the schema accepts. Fixed with base 10 on the String branch. The spec that
should have caught it used `"03"`, where octal and decimal agree.

**The two pinned artifacts disagree about a KSeF number, and each is right.** The OpenAPI
contract's `KsefNumber` pattern admits the NIP issuer form alone:

```
^([1-9](\d[1-9]|[1-9]\d)\d{7})-…
```

The FA(3) XSD's `TNumerKSeF` admits two more (XSD patterns are implicitly anchored, so it
carries no leading `^`):

```
^([1-9]((\d[1-9])|([1-9]\d))\d{7}|M\d{9}|[A-Z]{3}\d{7})-…
```

They are not in conflict — they govern different things. The contract says what a **lookup
URL** may contain, and `Ksef::KsefNumber` serves lookups (`Invoices::Client#download`,
`UPO::Client#for_ksef_number`), so its narrowness is correct there. The XSD says what a
**document** may reference. Judging a document field by `KsefNumber::FORMAT` flagged an
XSD-valid `M123456789-…` reference as malformed, so tier 1 no longer judges the format at all
and tier 2 owns it. **Do not widen `KsefNumber::FORMAT` to "fix" this** — that would loosen
the lookup path against its own contract. The layouts are the same length either way, so §13's
CRC-8 input rule is unaffected.

A fourth, smaller finding of the same shape: {Serializer} compared `values.keys.map(&:to_s)`
against the schema when rejecting unknown element names, but wrote with `values.key?(name)`
against a String. A symbol key therefore passed the check and was then **silently dropped**.
Keys are normalised once, at the top of `write_children`.

### 8.5 The advance-payment pair, `ZAL` and `ROZ`

Source: the pinned FA(3) XSD for the structure, and the Ministry's `ZAL`, `ROZ`, `KOR_ZAL` and
`KOR_ROZ` samples of §1.5 for what they contain. Recorded 2026-08-25.

A `ZAL` documents money received **before** the goods are delivered; a `ROZ` — art. 106f ust. 3
— is the invoice issued once they are, settling what the advance invoices already covered. Two
elements carry that, and both sit in `Fa` outside the correction group:

| Element | Occurs | Carried as |
|---|---|---|
| `Zamowienie` | 0–1 | `Invoice#order` |
| `Zamowienie/WartoscZamowienia` | 1, `TKwotowy` | `Order#total` |
| `Zamowienie/ZamowienieWiersz` | **1–10 000** | `Order#lines` |
| `FakturaZaliczkowa` | 0–**100** | `Invoice#advances` |
| `ZaliczkaCzesciowa` | 0–31 | **not modelled** — see below |

**A `ZAL` need not carry `FaWiersz`, and the Ministry's does not.** `Zamowienie` is
*"zamówienie lub umowa, o których mowa w art. 106f ust. 1 pkt 4"* — the order or contract — and
its positions stand in for invoice rows, in the currency the advance invoice was issued in.
Przykład 10 carries two `ZamowienieWiersz` and no rows. **The schema permits rows even so**:
`FaWiersz` is `minOccurs="0"`, described as *"węzeł opcjonalny dla faktury zaliczkowej"* —
optional, not forbidden. Nothing here refuses a `ZAL` with rows, and this paragraph reports one
witness rather than a rule. (An earlier revision stated it as a general fact; §8.4 declines to
build rules on single witnesses and the same discipline applies here.)

**`WartoscZamowienia` is not `P_15`, and confusing them would be a large error.** It is
*"wartość zamówienia lub umowy z uwzględnieniem kwoty podatku"* — the whole order **including
tax**. In Przykład 10 it is `375 150` against a `P_15` of `20 000`: the order is the contract,
`P_15` is the money received so far.

**An order position states its own tax.** `ZamowienieWiersz` carries both `P_11NettoZ`
(*"wartość zamówionego towaru lub usługi bez kwoty podatku"*) and `P_11VatZ` (*"kwota podatku
od zamówionego towaru lub usługi"*). `FaWiersz` has no per-row tax element and the tax is
computed from `P_12`; here the document carries both, so `OrderLine` reads both and derives
nothing. `StanPrzedZ` is `StanPrzed`'s twin, for a `KOR_ZAL` correcting an order position.

**`FakturaZaliczkowa`'s choice is inverted from `DaneFaKorygowanej`'s.** There, the marker
pairs with the KSeF number. Here it pairs with the plain one:

- in KSeF → `NrKSeFFaZaliczkowej` **alone**;
- outside KSeF → `NrKSeFZN` (*"znacznik faktury zaliczkowej wystawionej poza KSeF"*) followed
  by `NrFaZaliczkowej`.

So the two branches name *different fields*, and {AdvanceInvoice} carries both with exactly one
required — unlike {CorrectedInvoice}, where one nil-able field was enough. Getting this
backwards is easy and produces a schema-valid document asserting the wrong provenance.

#### Both types state their summary, measured rather than assumed

`Invoice::STATED_TOTALS_TYPES` gains `ZAL` and `ROZ`. Over every sample of each, the stated
buckets **never** equal the row totals:

| Sample | Type | Σ row `P_11` | Σ stated `P_13_*` | `P_15` |
|---|---|---|---|---|
| Przykład 10 | `ZAL` | — (no rows) | 16 260.16 | 20 000 |
| Przykład 14 | `ROZ` | 312 000.00 | 284 277.75 | 307 635 |
| Przykład 17 | `ROZ` | 312 000.00 | 277 222.45 | 300 000 |
| Przykład 11 | `KOR_ZAL` | — (no rows) | 2 221.34 | 0 |
| Przykład 18 | `KOR_ROZ` | 624 000.00 | 7 055.30 | 7 635 |

A `ZAL` has nothing to derive from. A `ROZ` describes the goods in its rows and states the
amount **remaining after the advance** in its buckets — and the advance is not in this
document, so the model could not compute it even in principle. `ZaliczkaCzesciowa`'s own
documentation confirms the shape: *"różnica kwoty w polu P_15 i sumy poszczególnych pól P_15Z
stanowi kwotę pozostałą ponad płatności otrzymane przed wykonaniem"*.

Tier 1 therefore requires a stated summary whenever an order is present or an advance invoice
is settled — the same rule, and the same module, as the `state_before` case of §8.4b. All three
triggers are **structural**: an element the document either carries or does not. Whether the
figures then reconcile is tier 3's, and tier 3 is not built.

#### What is deliberately not modelled

- **`ZaliczkaCzesciowa`** — instalments of a partial advance. It appears in **none of the
  twenty-six samples**, so there is nothing to build against; it is a whole element and is
  therefore visible through `#unmapped_elements`.
- ~~**`P_15ZK` / `KursWalutyZK`**~~ — **modelled 2026-08-26**, with `KOR_ZAL` and `KOR_ROZ`.
  See §8.6.
- **`Platnosc`** and **`DodatkowyOpis`** — payment details and free-form key/value notes. Both
  appear across `VAT`, `ZAL` and `ROZ` alike and have never been modelled; both are
  path-visible. `Platnosc` on a `ZAL` carries *when* the advance was paid, which is worth
  having eventually, but it is not what makes a `ZAL` a `ZAL`.


### 8.6 The last three types, and the row that states no amount

Recorded 2026-08-26, when `UPR`, `KOR_ZAL` and `KOR_ROZ` landed. **All seven `RodzajFaktury`
values are now modelled**, and twenty-two of the Ministry's twenty-six samples parse,
re-serialise, validate and round-trip. The four that do not are refused for a *construct* —
two priced gross, two identifying their buyer by something other than a NIP — not for a type.

Two of the three needed almost nothing new. `KOR_ZAL` is the correction group of §8.4 plus the
`Zamowienie` of §8.5; `KOR_ROZ` is the correction group plus `FakturaZaliczkowa`. Between them
they added one element:

**`P_15ZK` means two different things, and the invoice type decides which.** Its documentation
reads *"W przypadku korekt faktur zaliczkowych - kwota zapłaty przed korektą. W przypadku
korekt faktur, o których mowa w art. 106f ust. 3 ustawy - kwota pozostała do zapłaty przed
korektą"* — the amount **paid** before the correction on a `KOR_ZAL`, the amount **left to
pay** before it on a `KOR_ROZ`. One element, two readings. `Correction#paid_before` carries the
figure and does not try to name it more precisely than the schema does. All four `KOR_ZAL` and
`KOR_ROZ` samples carry it; `KursWalutyZK`, which sits in the nested sequence it opens, appears
in none of the twenty-six.

#### `UPR` needed a row that states no amount at all

A simplified invoice under art. 106e ust. 5 pkt 3 names the goods and stops. Both Ministry
samples are exactly that:

| Sample | The whole row | Summary |
|---|---|---|
| Przykład 15 | `NrWierszaFa`, `P_7` | `P_13_1`, `P_14_1`, `P_15` |
| Przykład 16 | `NrWierszaFa`, `P_7`, `P_12` | `P_15` alone |

Every child of `TFaWiersz` but `NrWierszaFa` is `minOccurs="0"`, so this is not a special case
in the schema — it is the schema's default, and the model was the thing being strict. `Line`
now carries every field optionally, and **`Line#net` answers `nil` rather than raising**: "the
row states no amount" is a state the model has to hold, and it is not the same as zero.

**The same shape unblocked Przykład 7**, the one Ministry correction this model could not read
— its single row names goods, a `CN` code and a quantity, with no amount anywhere. So all five
corrections now go through, and the refusal that used to name it is gone.

#### What replaced the refusals, and why it had to

`RowReader` used to refuse two shapes: a row with no price, and a row with no `P_12`. Both are
now read, because both are legal and the parser is documented not to validate. But an unpriced
row on an invoice that *derives* its summary from its rows is a real hazard — the amount is
simply absent from the tax base, and **neither tier can see it**: the XSD is blind to
arithmetic, and `#unmapped_elements` to values. That is the §8.4b bug class again.

So tier 1 took it over, addressed to the line and scoped to where it costs something:

| Row states | On a deriving invoice | On one that states its summary |
|---|---|---|
| amount + rate | fine | fine |
| amount, no rate | **reported** — no bucket to put it in | fine |
| no amount | **reported** — absent from the tax base | fine, this is `UPR` |

`Invoice#net_by_rate` skips what it cannot place, which is exactly why the rule is needed:
without it the document would quietly understate.

The one shape still refused at parse time is **gross pricing** (`P_9B`/`P_11A`), and the
distinction is worth keeping: a gross-priced row carries a number this model has nowhere to
put, so reading it would drop a real amount. An unpriced row carries no number to drop.


---

## 9. Still unverified

Carried forward; must be resolved before the code that depends on them is written
(DESIGN.md §0 rule 2). Reviewed 2026-08-23 (second pass, after the crypto module).

- **Business-rule catalogue** for validation tier 3 (DESIGN.md §7.7). Still the only
  genuinely open blocker of the original set, and now **known to be absent rather than
  merely unread**. This bullet used to say `faktury/weryfikacja-faktury.md` was the next
  place to look. It was pinned 2026-08-24 and it is not that document: it specifies
  *technical admission* checks, which turned out to be the missing first-tier source for
  tier **1**. See §15 for what it does settle, and §15.6 for the search that establishes no
  file at commit `1c34fe27` states a reconciliation rule — plus the three possible
  groundings for tier 3 and which of them is safe to build on.
- **Error-code catalogue.** Still open, but **narrowed again**: the *authentication
  operation* status codes are recorded at §4.8 **from the pinned contract** — not, as this
  bullet used to say, from the reference implementation; see §4.8 for why that distinction
  cost us code 480 — and the
  per-endpoint `ExceptionResponse` codes now known — and `docs/errors.md` lists all four —
  are `21405` (input validation),
  `21470` (unknown or withdrawn key, §10.2), `21111` (invalid authorisation challenge,
  §4.5) and `21157` (invalid package part size). The rest must be collected from the spec
  per operation, or observed — **and the collection is mechanical**: each operation's `400`
  response carries a Markdown table of its own codes in the `description`, which is where
  `21111` came from. The C# client has sibling files (`CertificateStatusCodeResponse`,
  `InvoiceInSessionStatusCodeResponse`, `OperationStatusCodeResponse`,
  `InvoiceExportStatusCodeResponse`) that will likely close the corresponding areas the
  same way when those subsystems are built.
- ~~**Whether the KSeF-token timestamp is really enforced as a replay nonce.**~~ **Resolved
  2026-08-24: it is.** §4.5 recorded the claim from first-tier documentation and nothing
  offline could test it. `spec/integration/crypto_spec.rb` authenticates with a deliberately
  stale `timestampMs`, and live TEST refused it (run `32704511675`). The claim is now
  observed, not believed.
- ~~**Whether `certificateId` and `publicKeyId` are derived as §10.2 states.**~~ **Resolved
  2026-08-24: both are.** The library never computes either — it echoes the server's
  `publicKeyId` back — so no offline test could check the derivation.
  `spec/integration/crypto_spec.rb` recomputes both from the real certificates and they
  match: `publicKeyId` is the Base64 SHA-256 of the DER `SubjectPublicKeyInfo`,
  `certificateId` the Base64 SHA-256 of the DER certificate (same run).
- **Nightly higher rate limits** (§6.1) — the 20:00–06:00 values are explicitly
  unpublished pending production tuning. Do not hard-code a nightly multiplier.
- ~~**Whether `upo.pages[].downloadUrl` arrives absolute or host-relative**~~ — **resolved
  2026-08-24: it arrives ABSOLUTE.** Observed on the first live nightly (run
  `32692339217`), which reported it explicitly. `Ksef::UPO::Client` handles both forms and
  will keep doing so — `srodowiska.md` promises only that a returned URL's *host* matches
  the environment called, not that the URL is absolute, so the relative branch stays as
  defence rather than dead code. (An earlier revision of this bullet said the field
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

`faktury/weryfikacja-faktury.md` states the same parameters as an admission requirement —
a fifth witness, and the first from first-tier prose (§15.5). It writes the wrapping as
"RSAES-OAEP (SHA-256/MGF1)", pairing the two digests in one breath, which is exactly the
distinction the MGF1 row below exists to defend.

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

**What is asserted instead** (implemented 2026-08-23, `spec/ksef/crypto_spec.rb` and
`spec/ksef/crypto/encryptor_spec.rb`), replacing DESIGN.md §6.4's "port three vectors from
the C# client":

| Parameter | How it is pinned |
|---|---|
| AES-256-CBC | **NIST SP 800-38A F.2.5** CBC-AES256.Encrypt, four blocks, byte for byte |
| PKCS#7 | the padded output is one block longer than an exact multiple of 16 |
| SHA-256 | **FIPS 180-4** vectors for `"abc"` and the empty string |
| OAEP digest | the longest accepted plaintext is **190 bytes**, i.e. `k − 2·hLen − 2` with `hLen = 32`. With SHA-1 it would be 214, so this pins the digest without trusting the option name |
| MGF1 digest | a ciphertext produced with MGF1-SHA-256 **fails** to decrypt under MGF1-SHA-1, so the two are genuinely distinguishable and the option is not being ignored |

The MGF1 row is the one that matters most. OpenSSL's MGF1 digest defaults to SHA-1, so
setting `rsa_oaep_md` alone silently produces OAEP-SHA256-with-MGF1-SHA1 — a different
scheme, which fails only at the far end. Verified on both 3.2.11 and 4.0.6.

### 10.2 Public key distribution and rotation

Source: `bezpieczenstwo/klucze-publiczne-do-szyfrowania.md` (05.05.2026).

`GET /security/public-key-certificates` is **unauthenticated** — the contract declares no
global `security` and none on the operation, the same reading that §6a.1 applied to
`/testdata/*`. So keys can be fetched before a credential exists, which is what makes the
KSeF-token flow possible from a cold start. Its ceiling is **60 req/s**, matching
`/auth/challenge` rather than the 10/30/120 default of §6.1. It returns a list of:

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

### 10.3 Decisions this gem made, that upstream does not state

Recorded here so they are not mistaken for ledgered facts, and so the reasoning survives.
Implemented 2026-08-23 in `lib/ksef/crypto/`.

| Decision | Value | Why |
|---|---|---|
| Certificate cache TTL | **one hour**, `PublicKeys::DEFAULT_TTL` | §10.2 says "not indefinitely" and nothing more. An hour fetches once per process in practice while bounding how long a withdrawn key can linger; `refresh!` and `with_key_rotation` cover the rest |
| `publicKeyId` | **always sent**, though the contract marks it nullable | It names *which* published key did the wrapping. Omitting it turns a key rotation from a `21470` you can remediate into an undecryptable payload with nothing to diagnose |
| Unparseable `validFrom`/`validTo` | the certificate becomes **unselectable** | Fail closed. A nil window must not read as "no constraint" — that would wrap a payload under a key KSeF may already have withdrawn |
| Unknown `usage` string | raises, rather than selecting nothing | A typo would otherwise present as "the Ministry publishes no such key", sending the reader to look for a rotation that never happened |
| `Ksef::CryptoError` | a new branch of the DESIGN.md §6.7 hierarchy | Neither an `ApiError` (the request succeeded; the list has nothing usable) nor a `ConfigurationError` (documented as local and pre-request). The same reasoning that added `AuthorizationError` and `ResourceGoneError` (§7 item 4) |
| Wrapping is done **by** the certificate | `Certificate#encrypt` | Keeps the public key and the OAEP parameters in one place, so no caller can wrap with the right key under the wrong padding |

One more, and it is the one worth stating: `Encryptor#seal` returns the ciphertext **and**
the hash-and-size of both forms in a single object. §11.1 requires four integrity values
per invoice and hashing the wrong artifact is silent — only the server can detect it — so
the two digests are produced together rather than left to a caller to pair up.

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

Independently confirmed by `faktury/weryfikacja-faktury.md`, which lists "computing and
verifying the hash of the invoice together with the file size" and the same for the
encrypted invoice among the checks KSeF performs (§15.5). All four values are the
service's, not ours to interpret.

### 11.2 Session open request

`OpenOnlineSessionRequest` = `formCode` + `encryption` (pinned spec, `components.schemas`).
`formCode` is the triple `systemCode` / `schemaVersion` / `value` — for FA(3) that is
`FA (3)` / `1-0E` / `FA`, consistent with §8's finding that `KodFormularza` is `FA` and
`FA (3)` is the `kodSystemowy`. `encryption` is `EncryptionInfo` =
`encryptedSymmetricKey` + `initializationVector` + `publicKeyId`.

**Send `X-KSeF-Feature: upo-v4-3` with it** — see §14.6. The header is not in the contract,
but both reference clients send it, and it selects which UPO format the session will
produce. Since this gem pins `upo-v4-3.xsd`, staying silent means accepting whatever the
server defaults to, which may not be the version we can validate.

### 11.2a Decisions this gem made about sessions, that upstream does not state

The counterpart to §10.3, kept beside the subsystem it governs. Recorded so they are not
mistaken for ledgered facts, and so the reasoning survives the person who had it.
Implemented 2026-08-23 in `lib/ksef/sessions/`.

| Decision | Value | Why |
|---|---|---|
| **The `Encryptor` is bound to the `Session`** | `Session` carries the encryptor that opened it; `#send_invoice` takes no key | The single most consequential one — see below |
| Session lifetime in the composite | **a fresh session per `send_invoice`**, with `client.session { }` for batching | Decided by the human, 2026-08-23. Reasoning in DESIGN.md §6.5 |
| Bearer fetched per request | `#bearer` is called on each call, not captured at construction | A 12-hour session outlives a "kilkanaście minut" access token, so a long run must pick up {Auth::AccessToken}'s proactive refresh mid-flight |
| Reference numbers shape-checked | character-set match before path interpolation | Keeps a garbled or hostile value out of a URL. Deliberately *not* a §13 checksum check: §12 warns the non-KSeF-number forms are unverified against that algorithm |
| `X-KSeF-Feature` opt-out | `upo_version: nil` omits the header | The header itself is contract-silent (§14.6), so a caller must be able to decline our guess about it |
| Granular layer is stateless | `Sessions::Online` holds no session | Not a decision so much as a copied one: both official clients thread the reference through as a parameter, and it matches `Auth::Client` |

**Why the encryptor belongs to the session.** The symmetric key is agreed *once*, in the
session-open request, and every invoice in that session is encrypted under it. So an invoice
encrypted with any other key is undecryptable at the far end — and the only symptom is
per-invoice status **435, "błąd odszyfrowania pliku"** (§12.1), which arrives
**asynchronously**, long after the send returned `202`. There is no synchronous error and
nothing in the response to inspect.

A `send_invoice(session, xml, encryptor:)` signature would make that mistake a plausible
typo. Binding the encryptor to the `Session` at open time makes it unrepresentable instead:
there is no way to name the wrong key, because the caller never names one. This is the same
move as {Ksef::Crypto::Encryptor#seal} returning both digests together (§10.3) — where a
mistake is silent and remote, prefer an API shape that cannot express it over a comment
warning against it.

### 11.3 Accepted schema versions differ by environment

Source: `srodowiska.md` (16.03.2026). **TEST accepts FA(2) as well as the current schemas;
DEMO and PROD reject FA(2).** That is the trap worth remembering: an integration validated
solely against TEST can be sending a schema production will refuse.

**The exact `formCode` triples come from the pinned contract, not from the prose**
(corrected 2026-08-23 — `srodowiska.md` spells the PEF codes `FA_PEF(3)` / `FA_KOR_PEF(3)`,
which are not the values the API accepts, and omits `FA_RR (1)` altogether).
`OpenOnlineSessionRequest.formCode` declares exactly five:

| `systemCode` | `schemaVersion` | `value` |
|---|---|---|
| `FA (2)` | `1-0E` | `FA` |
| **`FA (3)`** | **`1-0E`** | **`FA`** |
| `PEF (3)` | `2-1` | `PEF` |
| `PEF_KOR (3)` | `2-1` | `PEF` |
| `FA_RR (1)` | `1-1E` | `FA_RR` |

FA(3) is the row this gem sends, and it is consistent with §8's finding that
`KodFormularza` is `FA` while `FA (3)` is the `kodSystemowy` — note the space before the
bracket in both. Take these three strings from the table above rather than assembling them,
and never from `srodowiska.md`.

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

### 12.1 Status codes — three separate tables, all from the pinned contract

Retrieved 2026-08-23 from the contract's `SessionInvoiceStatusResponse.status` and
`SessionStatusResponse.status` descriptions. Sourced from the contract deliberately, and not
from `InvoiceInSessionStatusCodeResponse.cs`, after §4.8's lesson — and the caution paid:
the C# enum lists `400`, `401` and `403` for invoice status, which **the contract does not
declare at all**.

**Per invoice, in a session.** **Both `100` and `150` mean keep polling** — corrected
2026-08-23, having first been written here as "`150` is the only one". That came from
`OnlineSessionUtils.cs`, whose poller returns as soon as the code is anything but `150`, and
it is wrong on the contract's own wording: `100` is *"przyjęta do dalszego przetwarzania"* —
accepted for **further** processing — which is by definition not a final state, and an
invoice sitting at `100` has no KSeF number yet. A poller that stops there reports a
pending invoice as though it were decided.

So the rule this gem uses is **`code < 200` is in progress**, rather than a list of
intermediate codes. That is deliberately the opposite of §4.8's
treat-the-unknown-as-terminal rule for authentication, and the asymmetry is justified:
authentication polls without a deadline, so an unrecognised code there must not loop for
ever, whereas session polling is deadline-bounded, so an unknown intermediate code costs at
worst one timeout — and "unresolved" is a more honest answer about an invoice than
"prematurely final".

| Code | Meaning | Notes |
|---|---|---|
| **100** | **accepted for further processing** | **not terminal — keep polling** |
| **150** | **processing** | **not terminal — keep polling** |
| 200 | success | terminal, and the invoice has a KSeF number |
| 405 | processing cancelled because the session failed | |
| 410 | invalid permission scope | |
| 415 | cannot send an invoice with an attachment | |
| 430 | invoice file verification error | |
| **435** | **file decryption error** | what a wrong key or IV produces — see below |
| **440** | **duplicate invoice** | carries `originalSessionReferenceNumber` and `originalKsefNumber` |
| 450 | invoice semantic verification error | the business-rule tier rejecting it |
| 500 | unknown error | |
| 550 | cancelled by the system; retry later | retryable |

Two of those earn their emphasis. **`435` is the code a §14.1 mistake produces** — prefix the
IV to the ciphertext as upstream's prose instructs and this is what comes back, which makes
it the single most useful code to surface verbatim. And **`440` is the only status carrying
extensions**: on a duplicate the API hands back the session and KSeF number of the *original*
submission, which is exactly what a caller needs to recover rather than guess. Do not discard
those fields.

**Per session** — and the two session types have **different tables**, which is easy to miss.

| Code | Interactive | Batch |
|---|---|---|
| 100 | session open | batch session started |
| 150 | — | processing |
| **170** | **session closed** | — |
| 200 | processed successfully | processed successfully |
| 405 | — | package element verification error |
| 415 | error decrypting the supplied key | error decrypting the supplied key |
| 420 | — | invoice-per-session limit exceeded |
| 430 | — | archive decompression error |
| 435 | — | error decrypting archive parts |
| 440 | cancelled — no invoices sent | cancelled — send window exceeded, or no invoices sent |
| 445 | verification error, no valid invoices | verification error, no valid invoices |
| 500 | — (batch only) | unknown error |

Three consequences for the online session layer:

- **`170` exists only for interactive sessions**, and interactive has no `150`. A poller
  written against the batch table would wait for a code that never arrives.
- **`415` at session level is the RSA-OAEP wrap failing** — the server could not decrypt the
  symmetric key. Distinct from the per-invoice `435`, which is the AES payload failing. Those
  two codes localise a crypto fault to either the key or the payload, which is worth
  surfacing rather than collapsing.
- **`440` "no invoices sent" means an opened-and-unused session is cancelled**, so opening
  one speculatively is not free.

### 12.2 The reference clients' polling defaults, and why ours differ

Both clients poll on a **fixed 1-second interval up to 60 attempts** — a 60-second ceiling —
and treat `150` as the sole continue condition (`OnlineSessionUtils.cs`:
`DefaultSleepTimeMs = 1000`, `DefaultMaxAttempts = 60`, `ProcessingStatusCode = 150`).

DESIGN.md §6.5 specifies capped exponential backoff instead — 1s, 2s, 4s … 30s, with a
five-minute default deadline. Keep ours, for two reasons the reference clients do not have to
care about: a library shared across many callers should not spend a per-hour rate budget at a
fixed 1/s (§6.1 caps `GET /sessions/{ref}` at 1200/h, which 60 polls per invoice would eat
quickly), and a 60-second ceiling is too short for a large session. Their *terminal condition* needed
correcting too — see §12.1: **`code < 200` is in progress**, because `100` means "accepted for
further processing" and a poller stopping there reports a pending invoice as settled. This
sentence said "poll while the code is `150`" until 2026-08-23, the fourth copy of that claim
to survive a correction pass.

### 12.3 Decisions this gem made about UPO retrieval, that upstream does not state

The third of these tables, after §10.3 (crypto) and §11.2a (sessions). Implemented
2026-08-23 in `lib/ksef/upo/`.

| Decision | Value | Why |
|---|---|---|
| **A separate, credential-free connection** | `HTTP::Connection.storage` — no bearer, no `base_url` | §14.2 forbids sending the access token to a `downloadUrl`. A rule nobody can break beats a rule everybody must remember — see below |
| **No parsed form on `Document`** | holds the received `String`; no `#to_xml`, no re-encode, `#write` uses `binwrite` | The Ministry's XAdES signature covers **octets**. A lossless XML round-trip can still yield a document that no longer verifies, so the parsed form is simply not offered |
| `Ksef::IntegrityError` | a new branch of DESIGN.md §6.7 | A hash mismatch means *fetch it again* — nothing is wrong with the request, the credentials or the document. Not a `ValidationError` (the caller's data is fine) nor an `ApiError` (the response was a success) |
| `#verifiable?` separate from `#verified?` | two booleans, not one tri-state | "Nothing to check" and "the check failed" need different responses. **Corrected 2026-08-23:** this row used to justify the split by claiming the metered route publishes no hash. It does — §5.5 records the header on four `200` responses, all three UPO routes and the invoice download — and the client was discarding it. Both paths now verify; the split still earns its place for a response that genuinely omits the header |
| `#fetch` prefers the link | falls back to the metered route on expiry or absence | §14.2's resolution, in one call: the link is unmetered and hash-verified, and `GET /sessions` already allows only 10/min |
| A relative `downloadUrl` is resolved | against the API host; an absolute one used untouched | §9 still carries which form the live API sends as unverified, so both are handled rather than one guessed at |
| KSeF numbers parsed before use | `for_ksef_number` runs §13's CRC-8 first | A mistyped number fails locally instead of as an opaque 404 |
| `Ksef::Client#upo` uses the **metered** route | against this section's own preference for the link | Deliberate, and only for a single invoice: obtaining the unmetered link costs a metered status call first, so the direct route is one request against two. `#collective_upo` and `UPO::Client#fetch` prefer the link, where it pays |

**Why the connection split is the mechanism and not just tidiness.** A `downloadUrl` is a
pre-signed Azure Blob URI that carries its own authorisation in the query string. Sending
the KSeF access token to it would hand a live credential to third-party storage, and the
contract says so explicitly — *"nie należy wysyłać tokenu dostępowego"*. That is a rule
about something absent, and absences are exactly what code review misses: nobody notices
the header that was not removed. Putting those requests on a connection that has no bearer
to attach turns "we remembered" into "we cannot", which is the same reasoning as binding the
encryptor to the session (§11.2a) and having `Encryptor#seal` produce both digests at once
(§10.3).

Reference numbers share a shape: `YYYYMMDD-XX-<hex>-<hex>-CC`, where `XX` is a kind tag
(`CR` challenge, `SB` batch session, `EU` UPO) and `CC` looks like the same CRC-8 checksum
as §13. Only the KSeF-number form is documented; **do not validate the others against §13's
algorithm** without verifying it first.

---

## 13. KSeF number structure — verified with a working example

Source: `faktury/numer-ksef.md` for the structure, **corrected against the pinned contract
2026-08-23** for the length — see §13.1. The 2.0 format, 35 characters:

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

### 13.1 A 36-character legacy form exists, and the prose does not mention it

Found 2026-08-23, by a documentation review checking the code against the contract rather
than against this section. **`components.schemas.KsefNumber` declares
`minLength: 35, maxLength: 36`**, with the pattern

```
…-([0-9A-F]{6})-?([0-9A-F]{6})-([0-9A-F]{2})$
```

— an **optional hyphen splitting the technical part 6-6** — and says outright: *"Numer KSeF
o długości 36 znaków jest akceptowany, by zachować kompatybilność wsteczną z KSeF 1.0. W
KSeF 2.0 numery są generowane wyłącznie w formacie 35-znakowym."*

So both forms are accepted on input; only the 35-character form is ever *generated*. The
prose this section was built from says "always exactly 35", and the contract outranks it
(§0 rule 2). This was a real defect, not just drift: `KsefNumber.parse` enforced 35, and
both `Invoices::Client#download` and `UPO::Client#for_ksef_number` parse before use — so a
KSeF 1.0-era number could not be looked up at all, failing locally where the API would have
answered 200.

**The CRC input rule for the 36-character form is unverified.** §13's rule is "the first 32
characters, everything before the final hyphen", which is specific to the 35-character
layout; for the longer form that span is 33 characters and includes an extra hyphen, and
nothing upstream says whether the checksum covers the hyphenated or the de-hyphenated text.
Two consequences, both implemented:

- `KsefNumber.parse` accepts both forms, so a lookup is possible either way.
- It **verifies the checksum only on the 35-character form**, where the rule is known, and
  reports `#checksum_verified?` so a caller can tell a checked number from an accepted one.
  Guessing the legacy rule and rejecting on a mismatch would turn an unverified assumption
  into a hard failure on numbers the API accepts.

The pattern also carries facts §13 never recorded: the NIP part is *structural*
(`[1-9](\d[1-9]|[1-9]\d)\d{7}` — first digit non-zero, positions 2–3 not both zero) and
the date part constrains year, month and day ranges. Both are stricter than this gem's
`\d{10}` and `\d{8}`, though `Date.strptime` already rejects impossible dates.

**Fourth time prose has lost to the contract in this project** — after the `480` auth status
code (§4.8), the `formCode` table (§11.3) and the `100`/`150` polling rule (§12.1). The
standing lesson, now stated once here rather than rediscovered a fifth time: **when a fact
comes from upstream prose, check the OpenAPI schema for the same field before ledgering it.**
The prose is a summary; the contract is the interface.

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

Four sources agree against it:

1. **The pinned OpenAPI spec** — `EncryptionInfo` carries `initializationVector` as a
   discrete field of the session-open request, alongside `encryptedSymmetricKey` and
   `publicKeyId`. Highest precedence. (2026-08-22)
2. **C#** — `EncryptBytesWithAES256` returns the encryptor's output directly, with no
   prepended bytes (`CryptographyService.cs:149–161`). (2026-08-22)
3. **Java** — `cipher.doFinal(content)`, likewise bare
   (`DefaultCryptographyService.java`). (2026-08-22)
4. **The contract's own worked example, arithmetically** (found 2026-08-23). The
   `POST /sessions/online/{ref}/invoices` example pairs `invoiceSize: 6480` with
   `encryptedInvoiceSize: 6496`. 6480 is 405 whole AES blocks, so PKCS#7 adds **exactly one
   block** of padding and lands on 6496. A prefixed 16-byte IV would have made it 6512.
   This is the sharpest of the four: it is a number upstream published about its own
   encryption, and it leaves no room for the IV. Asserted in
   `spec/openapi_contract_spec.rb`, and reproduced by `Encryptor` in its own spec.

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

### 14.6 A session-open header both clients send and the contract never mentions

Found 2026-08-23, by reading the reference clients before designing the session layer.

`X-KSeF-Feature: upo-v4-3` is sent on `POST /sessions/online` (and on `POST /sessions/batch`)
by **both** official clients. It selects the format of the UPO the session will eventually
produce.

| Source | Evidence |
|---|---|
| `ksef-client-java` | `DefaultKsefClient.openOnlineSession` sets `headers.put(X_KSEF_FEATURE, upoVersion.value())`; the `UpoVersion` enum holds `upo-v4-2` and `upo-v4-3`, and `fromValue` falls back to `upo-v4-3` |
| `ksef-client-csharp` | `OpenOnlineSessionAsync(..., string upoVersion = null)` adds `{ "X-KSeF-Feature", upoVersion }`; `IOnlineSessionClient` documents it as "Opcjonalna wersja formatu UPO. Dostępne wartości: `upo-v4-3`" |
| **Pinned OpenAPI contract** | **`X-KSeF-Feature` does not appear anywhere in the document.** `POST /sessions/online` declares no `parameters` at all, and the string `upo-v4-` occurs zero times |

This is the inverse of §14.4's situation: not upstream contradicting itself, but the contract
being *silent* about something both of its own reference implementations consider necessary.
Measured, not inferred — grep counts of zero in the pinned spec.

**Resolution: send `X-KSeF-Feature: upo-v4-3` explicitly on session open.** Three reasons.
This gem pins `upo-v4-3.xsd` and nothing else, so a session producing 4.2 would yield a
document we cannot validate. Java's enum proves the server still understands `upo-v4-2`,
so a default exists and is not ours to guess. And §14.3 already establishes that UPO
validation is delicate enough — TEST's own examples fail upstream's own schema — without
adding version drift to it.

Being contract-silent, this could not be checked offline, only observed — and it now has
been. **Verified against live TEST on 2026-08-24** (nightly run `32692339217`): a session
opened with the header returned a UPO in the `upo-v4-3` namespace, which is the one whose
schema this gem bundles. The header does what both reference clients assume, and this section
is no longer the least certain fact in it.

### 14.7 A real UPO fails upstream's UPO schema on its own signature

Found on the **first live nightly**, 2026-08-24 (run `32692339217`), and invisible to every
offline test before it.

A UPO is *"an XML document XAdES-signed by the Ministry of Finance"* (§12) — the signature is
what makes it proof of receipt. `upo-v4-3.xsd` **declares no `ds:Signature` element anywhere**,
so a genuine UPO validated against it reports:

```
Element '{http://www.w3.org/2000/09/xmldsig#}Signature': This element is not expected.
```

Every UPO KSeF has ever issued fails upstream's own schema, for the same reason §14.3's six
examples do — except this one is worse, because it applies to the real artifact rather than to
the published samples.

**And the samples are exactly why nobody noticed.** All six pinned worked examples are
**unsigned** — measured: zero `Signature` elements between them. Upstream publishes the
business content without the envelope, so the offline corpus cannot exhibit the defect that
every live document has. `spec/ksef/upo/validator_spec.rb` now signs one of them to close that
gap, so the next occurrence is caught without a live run.

**Resolution: `UPO::Validator` removes the enveloped signature from a *copy* before validating.**
Not leniency — an enveloped signature wraps the business document, and the schema describes the
business document, so setting it aside is what makes the remaining errors mean anything. §14.3's
environment-marker warning and every other violation still surface unchanged, and the caller's
bytes are never touched, which §12 requires. `UPO::Validator.signed?` exposes whether the
signature is there, since that distinguishes a real UPO from a published example.

**What this does *not* do is verify the signature.** Checking the Ministry's XAdES would need
its certificate chain and the W3C/ETSI schemas, which §1.2 keeps out of `lib/` on licensing
grounds. Validation here stays a diagnostic on content, exactly as the rest of §14.3 says.

---

## 15. Invoice verification — what KSeF checks on submission

Source: `faktury/weryfikacja-faktury.md` (dated 09.04.2026), pinned 2026-08-24 at the same
`ksef-api` commit `1c34fe27` as everything else in §1.3.

**Read this first: it is not the document §9 said it was.** §9 named this file as the place
to look for the **tier-3 business-rule catalogue** (DESIGN.md §7.7 — line sums against rate
summaries against `P_15`, correction references for `KOR`). It contains none of that. It is
a list of *technical admission* checks: XML shape, uniqueness, size, crypto, permissions.
§9 has been corrected, and §15.6 records where tier 3's catalogue actually is and is not.

What it does deliver is unexpectedly valuable in a different place: **tier 1 was the tier
with no first-tier source at all**, assembled from the schema plus judgement, and this
document specifies it exactly.

### 15.1 XML admission rules — and not one of them is a schema check

An invoice must satisfy all six. The right-hand column is the point of the table:

| Rule | Can tier 2 catch it? |
|---|---|
| Well-formed XML per XML 1.0 | **Only since 2026-08-24** — see the note below |
| UTF-8 **without BOM** (no leading `EF BB BF`) | **No** — a BOM parses fine |
| Conforms to the schema declared at session open | Yes — this *is* tier 2 |
| An XML prolog is optional, but if present must not declare a non-UTF-8 encoding | **No** |
| **No processing instructions** | **No** — PIs are legal XML |
| No discouraged Unicode characters: `[#x7F-#x84]`, `[#x86-#x9F]`, `[#xFDD0-#xFDEF]`, and `[#xNFFFE-#xNFFFF]` for every plane `N` = 1…10₁₆ | **No** |

Failing any one of them rejects the invoice.

**A correction to the first row, and it was a real defect.** The rule is not free: libxml2
parses in *recovery* mode by default, so a document with an unclosed root or trailing text
after it comes back as a usable tree — and that recovered tree validates clean against the
schema. `Ksef::FA3::Validator` never consulted `document.errors`, so `valid?` returned **true
for XML that is not XML**. Fixed 2026-08-24 by checking well-formedness first and reporting it
separately; before that fix, *five* of the six rules were invisible to this gem's tier 2, and
a tier-1 implementer reading this table would have skipped the one check the table promised was
already covered.

**Four of the six are invisible to tier 2 even now**, which is the argument for tier 1
existing at all — and it is not hypothetical. The C# client's own test corpus ships
`invoice-template-fa-3-with-disallowed-unicode-characters.xml`, now pinned to
`spec/fixtures/fa3/` (§1.4). Measured 2026-08-24:

- it is **XSD-valid** against our pinned FA(3) schema once its `#nip#` placeholder is
  substituted (§1.4) — `Ksef::FA3::Validator` returns zero errors, so tier 2 passes it;
- it carries **U+0087** and **U+009B**, both inside the forbidden `[#x86-#x9F]` range.

**Implemented 2026-08-24** as `Ksef::FA3::DocumentValidator` (validator tier 1b, DESIGN.md
§7.7). It runs on `#to_xml`'s output, before those bytes are hashed and encrypted — after that
point a rejection costs a round trip and a session. All four otherwise-invisible rules are
covered, plus the 1 000 000-byte ceiling of §15.5.

A schema-only validator ships that invoice, and the pinned rule above says KSeF rejects it.
**That rejection is derived, not observed** — it follows from *"Niespełnienie któregokolwiek z
powyższych wymagań spowoduje odrzucenie faktury"*, and nobody has submitted this fixture. (An
earlier version of this sentence justified it with "no session has ever reached live KSeF",
which §14.6 in this same document contradicts as of 2026-08-24: sessions reach it nightly. The
conclusion stands on the narrower ground.) One fixture, and it settles whether tier 1 is worth building.

**Where those characters come from matters more than the rule.** The offending text reads
`iloĹ›Ä‡` — that is `ilość` encoded as UTF-8 and then decoded as Latin-1. **Double-encoded
UTF-8 is the practical source of forbidden C1 characters**, not deliberate abuse. Any ERP
export that has been through one bad encoding conversion hits this, which makes it a
likely real-world rejection rather than an exotic one.

### 15.2 Duplicate detection is a three-field key, held for ten years

KSeF detects duplicates **globally**, not per session, on the combination:

1. seller NIP — `Podmiot1/DaneIdentyfikacyjne/NIP`
2. invoice kind — `RodzajFaktury`
3. invoice number — `P_2`

A duplicate returns per-invoice code **440** (§12.1's table, confirmed here from prose).
Uniqueness is retained for **ten full calendar years** counted from the end of the year of
issue.

Two consequences worth stating, because both are easy to get wrong:

- **`RodzajFaktury` is part of the key.** The same `P_2` under `VAT` and under `KOR` is not
  a duplicate. A correction therefore does not need a distinct number from the invoice it
  corrects.
- **The key is the seller's, not the issuer's.** Where branches, local-government units or
  authorised third parties invoice on behalf of one NIP, upstream says explicitly they must
  agree a numbering scheme between themselves. Nothing in the API prevents a collision;
  it surfaces as a 440 after submission.

### 15.3 NIP checksums are validated **in production only**

The sharpest fact in the document, and it is stated twice — once for
`Podmiot1`/`Podmiot2`/`Podmiot3`/`PodmiotUpowazniony`, and once for the NIP embedded in
`Podmiot3`'s `InternalId`. Both say *"Dotyczy tylko środowiska produkcyjnego"* — applies to
the production environment only.

Three consequences:

- **It explains `rake auth:bootstrap`.** §6a.1 invents a NIP and the flow works on TEST.
  That is not tolerance of a malformed identifier — checksum validation simply is not
  running there. (The bootstrap generates checksum-valid values anyway, which is why this
  never surfaced as a puzzle.)
- **A green TEST run proves nothing about NIP validity.** No integration spec can cover
  this rule, in either direction: TEST will not reject a bad NIP, and PROD is off limits
  from any test (a hard rule). It is verifiable by reasoning about the document and by unit
  tests of our own checksum, and by nothing else.
- **Keep `Ksef::FA3::NIP.validate!` running in every environment.** It is deliberately
  *stricter* than TEST. Do not add an environment check to relax it: production is where
  the rejection would land, and a gem that lets a bad NIP through on TEST has simply moved
  the failure to the worst possible moment.

### 15.4 The issue date may not be in the future

`P_1` must not be later than the date KSeF accepts the document.

Offline this can only be approximated: the comparison is against *KSeF's* acceptance date,
which is not knowable at build time, and a document issued today and submitted today sits
exactly on the boundary. So tier 1's rule is the safe half — **reject an issue date in the
future** — and the same-day boundary is left to the service. Do not implement this as an
equality against `Date.today` in the local zone; a client in a western timezone would
reject perfectly good invoices around midnight in Warsaw.

### 15.5 Facts this document corroborates — and one it establishes

Three of the four rows below were already in this ledger, resting on the contract or the
reference clients alone, so an independent witness is worth having. **The fourth is new**: the
batch-only attachment rule appears here for the first time, and the row says so rather than
claiming a confirmation it cannot make.

| Fact | Where it lives | What this document adds |
|---|---|---|
| AES-256-CBC, 256-bit key, 128-bit IV, PKCS#7; symmetric key under RSAES-OAEP **SHA-256/MGF1** | §10.1 | A **fifth** witness, and the first from first-tier prose. Note it writes "SHA-256/MGF1" as one unit, pairing the two digests exactly as §10.1 requires |
| Hash **and size** of both the plaintext and the encrypted invoice | §11.1 | Confirms all four values, and that the check is KSeF's, not decoration. Note upstream heads this rule *"Zgodność metadanych faktury **w sesji interaktywnej**"* — it is scoped to the interactive session; the batch flow of 0.2 will need its own reading |
| 1 MB (1 000 000 bytes) without attachments, 3 MB with; 10 000 invoices per session | §6.2 | Identical, plus batch: 50 ZIP files, 100 MB each before encryption, 5 GB per package. **Three of these carry an asterisk and are defaults, not ceilings of the format:** *"Jeżeli w scenariuszach biznesowych organizacji dostępne limity są niewystarczające, prosimy o kontakt z działem wsparcia KSeF"* — and `limity.md` heads the same numbers *"Wartość domyślna"*, with `GET /limits/context` reporting the live values. The asterisk attaches to 1 MB, 3 MB and 10 000; **not** to the batch ZIP figures. `DocumentValidator` takes `max_bytes:` for that reason: hard-coding the default as absolute rejected invoices KSeF would accept |
| Attachments are **batch-only** | *nothing — this is the first source* | DESIGN.md §7.4 only puts *operational* attachment constraints out of scope for 0.1; it never said batch-only, and no document here did. So this row is **new**, not a confirmation, and the section heading above overstates it. With one exception — an offline *technical correction* may use an interactive session — plus a requirement of prior opt-in in `e-Urząd Skarbowy`. Both are 0.2/0.3 concerns; recorded so the exception is not rediscovered |

### 15.6 Tier 3's catalogue is in none of the 77 files

Searched at commit `1c34fe27`: no document in `ksef-api` states a reconciliation rule.
Nothing says `P_15` equals the sum of the rate buckets, nothing constrains a `KOR`
document's references to the invoice it corrects, nothing gives an error code for an
arithmetic mismatch. The closest thing to a rule catalogue is this section, and it is
technical rather than semantic.

The FA(3) XSD does carry **683 `xsd:documentation` annotations** — every field described in
Polish, with citations to the VAT Act. They are a genuine first-tier source for what a
field *means* (that is where §8.1a's rate buckets came from). They state no equalities:
`P_13_1` is documented as "the sum of net sales values under the basic rate" and `P_15` as
"the total amount due", and the arithmetic relating them is left to the reader.

So tier 3 has three possible groundings, and they are not equal:

1. **Arithmetic that follows from the field definitions.** That `P_13_1` is a *sum* of the
   lines taxed at the basic rate is what the annotation says; checking it is not policy.
   This is the part that can be built now, and it needs no external catalogue.
2. **The Ministry's FA(3) brochure** (`broszura informacyjna`), published on
   `podatki.gov.pl` and **not** in any CIRFMF repository. This is where the published
   business-rule list DESIGN.md §7.7 asks for would come from. Pinning it means taking an
   artifact from outside the repositories §1 covers, under a licence nobody here has read.
3. **Observation against TEST.** Reliable, slow, and it only ever finds rules we thought to
   probe for.

**Why it does not exist yet, and where it will appear.** `CIRFMF/ksef-api` issue **#837**
(author `kw-cirf`, a collaborator) announced the **first business validation KSeF ever proposed**:
for `KodWaluty != PLN`, at least one `P_14_x` + `P_14_xW` pair must be filled, rejection status
**`425` "Faktura nie spełnia wymagań dotyczących danych"**, scheduled TEST 2026-07-21 / PROD
2026-07-28, *"to be added to `faktury/weryfikacja-faktury.md`"*. It was **withdrawn back to
analysis** after the community showed it rejects legal foreign-currency invoices carrying only
`np`/`zw`/`0%`/`oo`/margin rates. The live `weryfikacja-faktury.md` was diffed against our pinned
copy on 2026-08-24: **identical** — the section never landed. Two things follow. The catalogue's
future address is known (that file, plus status `425`), and the Ministry's own remark in the
thread — that not one production invoice violated the proposed rule — is evidence **KSeF today
enforces nothing beyond the schema**.

**And the error codes are not the catalogue either.** A natural hope is that a rejection code list
is the rule list seen from the failure side. It is not: the reference clients' catalogues
(`InvoiceInSessionStatusCodeResponse` and siblings) funnel *every* content violation into one
code — **`450` "Błąd weryfikacji semantyki dokumentu faktury"** — with free-text details. There is
no code for "totals do not reconcile" and none for a malformed correction reference.

**What the Ministry's samples add.** §1.5 records the measurement: `Σ P_13_* + Σ P_14_* == P_15`
holds in 24 of 26 official examples, failing on Przykład 1 by one grosz (bucket-level tax
rounding — *not* gross pricing, see §1.5)
and on Przykład 16 by omission (a `UPR` may carry `P_15` alone). That is *empirical* grounding —
grounding 3 — for a rule the text does not state, and it fixes the rule's shape: a tolerance of a
grosz and a guard for absent buckets, or it rejects the Ministry's own first example.

**Recommendation, for the human to decide (DESIGN.md §12):** build tier 3's engine now on
grounding 1, where the rule *is* the field definition, and let the catalogue grow — which
is what DESIGN.md §7.7 already anticipates with "the catalog grows over the gem's life".
Do not synthesise rules from Polish VAT law and record them as verified facts; that is
inference wearing a citation. Grounding 2 is a licensing and scope question, not a coding
one.

**§9's characterisation of this as "the next place to look" was reasonable and wrong.** The
lesson is the same one §1.3 already carries, pointed the other way: listing the upstream
tree found 73 unread files, and reading them resolved most of §9 — but it also means a
remaining gap is now much more likely to be genuinely absent than merely unread.
