# ksef_client — agent instructions

Read DESIGN.md fully before writing any code; follow its §0. It is the spec; this file is the cheat sheet.

Precedence when sources disagree: **pinned artifacts** (OpenAPI spec, FA(3) XSD) > `docs/REFERENCE.md` > DESIGN.md > this file > memory. The ledger is *derived* from the artifacts, so where it contradicts them the artifacts win and the ledger gets corrected (DESIGN.md §2).

## Status

- Current milestone: **Phase 2** (DESIGN.md §11). Phase 1 is complete — all three "Done when" gates pass: codegen reproducible, VAT golden file XSD-valid, CI matrix green.
- **Phase 2 order:**
  1. ~~`Ksef::FA3.build`~~ — **done.** `lib/ksef/fa3.rb` + `lib/ksef/fa3/builder.rb`. DESIGN.md §8's snippet runs verbatim and validates against the XSD; a spec asserts exactly that, so it stays true.
  2. ~~**Certificate/XAdES auth.**~~ — **done, and verified against live TEST 2026-08-23.** `Auth::TokenRequest`, `Auth::AuthorizationPolicy`, `Auth::Validator`, `Auth::Signer`, `Auth::SignatureTemplate`, `Auth::Xades`, `Auth::Client`. A KSeF token has been minted end to end with no external client, which resolves DESIGN.md §12 item 4 and confirms KSeF accepts our signature (`docs/REFERENCE.md` §6a.4). Two rules from this work that still bind: **validate before signing, never after** — a signed document can never be schema-valid (§14.5); and the signature shape is fixed by an allow-list (`docs/REFERENCE.md` §4.3), so do not "improve" the algorithms without re-reading it.
  3. ~~Crypto module~~ — **done.** `lib/ksef/crypto.rb` plus `crypto/{certificate,public_keys,encryptor,digest}.rb`, and with it the **KSeF-token auth flow** (`Auth::Token`, `Auth::Client#submit_ksef_token`), so both authentication methods now exist. No upstream golden vectors exist, as suspected: the primitives are pinned to NIST SP 800-38A F.2.5 and FIPS 180-4, and the two parameters that could silently go wrong are pinned behaviourally — the 190-byte OAEP plaintext limit fixes the digest at SHA-256, and MGF1-SHA-256 ciphertext provably fails under MGF1-SHA-1. **§14.1 gained a fourth witness**: the contract's own example pairs 6480 plaintext bytes with 6496 encrypted, which is one PKCS#7 block and no room for an IV. Client-side decisions upstream does not state are in `docs/REFERENCE.md` §10.3. **Not yet verified against live KSeF** — `spec/integration/crypto_spec.rb` is written but has only ever run against stubs.
  4. ~~Online sessions, send/status/UPO/download~~ — **done.** §8's snippet runs end to end against stubs (`spec/ksef/client_spec.rb`); **no session has ever reached live KSeF**, so Phase 2's first gate is still open. `spec/integration/session_flow_spec.rb` is the spec that closes it — it exists but has never run live, and until 2026-08-23 it did not exist at all while three documents claimed the nightly would settle the question. Built: `KsefNumber` (CRC-8 verified against the documented example), `Auth::AccessToken` (expiry from `validUntil`, *never* by decoding the JWT — §4.3 excludes the `jwt` dep), `Sessions::Online` (open/send/close), and `Sessions::Status` (single-shot reads plus deadline-bounded waits, with `InvoiceCodes`/`SessionCodes` and the `SessionState`/`InvoiceState`/`UpoPage` value objects), and `UPO::Client` + `UPO::Document` (both routes, integrity-checked, bytes kept verbatim — §12.3). `UPO::Validator` (§14.3 handled: the receiving-party mismatch is a **warning**, not an error, so all six pinned examples validate — and there is deliberately no `validate!`, because a UPO is legal proof of receipt and a schema check must never gate archiving it). Also built: `Invoices::Client` (`GET /invoices/ksef/{ksefNumber}` — 8/s but only **64/h**, so the number is CRC-checked locally rather than spending a request on a 404) and **`Ksef::Client`**, the §8 facade. Two things in the facade worth not undoing: `Receipt#reference` returns *self*, because every status and UPO endpoint is keyed on the session **and** the invoice, so a bare invoice reference looks nothing up; and `#upo` uses the *metered* per-invoice route against §14.2's stated preference, because obtaining the unmetered link costs a metered status call first — the link wins for collective UPOs, not single ones.
     - **Two decisions here are binding, both recorded at `docs/REFERENCE.md` §11.2a.** The `Encryptor` is bound to the `Session` rather than passed per send — a mismatched key is undecryptable at the far end and surfaces only as asynchronous per-invoice status `435`, so the API shape must make it unrepresentable. And `send_invoice` opens **a fresh session per call** (human decision, 2026-08-23), with `client.session { }` for deliberate batching; DESIGN.md §6.5 carries the reasoning.
     - **Poll while `code < 200`, not while `code == 150`** (§12.1). `100` is "accepted for *further* processing" — undecided, with no KSeF number yet — so a poller that stops there reports a pending invoice as settled. The reference clients get this wrong; do not copy them. Note too that **interactive sessions have no `150` at all — they use `170` for closed**, and `170` is not the end either, because closing starts asynchronous UPO generation.
  5. Validator tiers 1 and 3; then the remaining six invoice types, starting with KOR (§7.4).
- **DESIGN.md §12 item 4 is resolved (2026-08-23)** and the nightly schedule is live. `rake auth:bootstrap` provisioned a TEST credential, which established the thing no offline test could: **KSeF accepts this gem's XAdES signature**, and the 2.0 namespace choice was right (`docs/REFERENCE.md` §6a.4). Two bugs surfaced on the way, both ours — see §6a.3 (PESEL encodes a birth date; the checksum alone is not enough) and §6a.5 (a missing OpenSSL CA bundle reads as a broken *server* certificate; fix with `SSL_CERT_FILE`, never by disabling verification).
- **Steps 2–4 are no longer blocked.** They were, until the 2026-08-22 pass pinned the normative subset of `CIRFMF/ksef-api`'s prose documentation (`docs/upstream/`, ledgered at `docs/REFERENCE.md` §1.3). Crypto parameters, XAdES requirements, session semantics and the UPO format (`docs/REFERENCE.md` §10, §4.3, §11, §12) are all now sourced from first-tier documentation. **Only the tier-3 business-rule catalogue and the error-code catalogue remain open** (§9).
- The lesson worth keeping: `ksef-api` has **77 files**, and for a long time only 4 were pinned. Before declaring a fact unverifiable, list the upstream tree — most "unknowns" were prose nobody had read.
- Where upstream contradicts itself, `docs/REFERENCE.md` §14 has the resolution. **§14.1 in particular: the AES IV is *not* prefixed to the ciphertext**, despite `sesja-interaktywna.md` saying it is. Following the prose there produces undecryptable payloads.
- What is built: transport config/environments/errors/HTTP, FA(3) codegen + the `build` DSL, offline XSD validation for FA(3) *and* auth documents, the `AuthTokenRequest` document, the XAdES-BES signer, `Auth::Client` covering all six auth endpoint calls, the crypto module + KSeF-token credential, the online session layer (open/send/close plus status polling), UPO retrieval and validation, invoice download, and the `Ksef::Client` facade. **§8's snippet runs end to end** — against stubs. The XAdES flow is verified against live TEST (§6a.4); **everything else is verified only against WebMock stubs — no session has ever been opened against KSeF.** Still missing: validator tiers 1 and 3, and six of the seven invoice types.
- Also deferred: `docs/field_mapping.md` (see DESIGN.md §7.2 for why).

## Commands

Every command below needs this prelude first:

```bash
export PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8
```

rbenv's shims are not on `PATH` in a non-interactive shell — without the prefix, `bundle` resolves to macOS system Ruby 2.6.10 and dies. Without `LANG`, `File.read`/`JSON.parse` raise `Encoding::InvalidByteSequenceError` on the Polish text that pervades the KSeF specs and schemas.

- `bundle exec rake` — **the one to reach for.** Runs `verify:artifacts`, `fa3:verify`, `spec`, `rubocop`. This is the definition of done.
- `bundle exec rake verify:artifacts` — check pinned artifacts against `docs/artifacts.sha256`. A failure means **upstream changed**: investigate and ledger it, never "repair" the checkout.
- `bundle exec rspec` — unit + golden tests. Must never touch the network; `spec_helper` enforces that via WebMock.
- `bundle exec rspec spec/ksef/configuration_spec.rb:42` — single example while iterating.
- `bundle exec rubocop` — style authority. Not done until clean; prefer fixing over disabling cops.
- `KSEF_INTEGRATION=1 KSEF_ENV=test bundle exec rspec --tag integration` — live TEST suite. **Both** the env var and the tag are needed: RSpec ANDs exclusion filters with CLI inclusions, so the variable is what lifts the exclusion. Run only when explicitly asked; it is nightly-CI's job, and it reaches the network and consumes shared TEST state. `spec/integration/auth_flow_spec.rb` provisions a fresh test person per run rather than reusing `KSEF_TEST_NIP`, because re-authenticating an existing context by XAdES needs the PESEL that holds its permissions and that is not among the stored secrets.
- `KSEF_RELEASE_CHECK=1 bundle exec rspec` — adds the release gates in `spec/release_readiness_spec.rb`: gemspec invariants, the four approved runtime deps, and no reintroduced metadata placeholders. **Currently green — keep it that way.**

- `bundle exec rake auth:bootstrap` — **one-time, human-run.** Provisions a TEST credential: invents a checksum-valid NIP/PESEL, registers via the unauthenticated `/testdata/person`, authenticates by XAdES with a self-signed certificate, mints a KSeF token, and prints `KSEF_TEST_NIP` / `KSEF_TEST_TOKEN` for the **environment** secrets on `ksef-test` — not repository secrets, which every workflow in the repo can read (§6a.3). Refuses anything but TEST. The token it prints is a real credential — it goes straight into GitHub secrets, never into a file here. Logic lives in `tasks/ksef_bootstrap.rb` and is spec-covered against stubs (`docs/REFERENCE.md` §6a.3).
- `bundle exec rake fa3:generate` — regenerate `lib/ksef/fa3/generated/` from the pinned XSD. Output is **committed**; never hand-edit it. The generator lives in `tasks/fa3_generator.rb`, outside `lib/` so it is not packaged.
- `bundle exec rake fa3:verify` — regenerate and fail on any byte difference. Catches both a non-deterministic generator and a stale committed `generated/`. Part of the default task and of CI.

## Verifying the Ruby 3.2 floor

**RuboCop cannot do this, and must not be trusted to.** `TargetRubyVersion: 3.2` catches *syntax* — it does flag the `it` block parameter. It does **not** flag post-3.2 APIs: `Range#overlap?` (3.3), `Array#fetch_values` (3.4) and `MatchData#bytebegin` (3.4) all pass clean under this project's config. Relying on RuboCop here ships a gem that `NoMethodError`s on the declared floor, and the failure lands on users rather than CI.

Only running on 3.2 proves it. **Ruby 3.2.11 is installed**, so run it before declaring any milestone done (DESIGN.md §10):

```bash
export PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8
mv Gemfile.lock /tmp/Gemfile.lock.dev                 # lockfile is resolved under 4.0.6
BUNDLE_PATH=/tmp/ksef-bundle-32 RBENV_VERSION=3.2.11 bundle install
BUNDLE_PATH=/tmp/ksef-bundle-32 RBENV_VERSION=3.2.11 bundle exec rake
mv /tmp/Gemfile.lock.dev Gemfile.lock                 # restore
```

The separate `BUNDLE_PATH` keeps the 4.0.6 gem set intact, and resolving without the lockfile mirrors what CI does per matrix Ruby. Bundler under 3.2.11 is 2.4.19, which cannot read a lockfile written by Bundler 4.

Last verified green on 3.2.11 (2026-08-23, after the `Ksef::Client` facade): 799 examples, 0 failures, line 100 / branch 97.57 / method 100, RuboCop clean. **Check `rake`'s exit code, not just its output** — a coverage-floor failure prints among the RuboCop lines and is easy to read past; `rake exit=0` is the only reliable signal. This is how the skipped-gate bug described under **Workflow** below stayed hidden. The crypto primitives were measured on both 3.2.11 and 4.0.6 before any code was written — `OpenSSL::PKey::PKey#encrypt` with explicit OAEP options, the NIST and FIPS vectors, and the 190-byte OAEP limit all behave identically. One difference worth knowing: a wrong-padding decrypt raises `OpenSSL::PKey::PKeyError` on 4.0.6 but `OpenSSL::PKey::RSAError` on 3.2.11, so **rescue `OpenSSL::OpenSSLError`** in any spec asserting a crypto failure.

Even so, when reaching for any core or stdlib method, confirm it exists in 3.2 rather than assuming — a filtered local run will not catch it.

> **Settled 2026-08-22 — do not re-raise.** Ruby 3.2 is EOL, and it stays the floor anyway. The version-support policy's EOL-drop rule governs future series (3.3 onward), not this floor; the reasoning is in DESIGN.md §3. Do not propose raising the floor to 3.3, and do not treat 3.2's EOL as licence to use post-3.2 APIs.

## Hard rules — violating any of these means stop and flag

- Never invent KSeF endpoint paths, XML element names, namespace URIs, or crypto parameters. Verify against the pinned OpenAPI spec / XSD / CIRFMF docs and record value + source + date in `docs/REFERENCE.md` first.
- Never target the PROD environment from any test or script. Integration code must hard-fail on `KSEF_ENV=prod`.
- **Only GET and HEAD are ever auto-retried.** Every POST/PUT/PATCH/DELETE surfaces its error to the caller — a duplicate invoice in KSeF is a real tax problem. Enforced by `Ksef::HTTP::Retry`, which delegates every decision to `Ksef::RetryPolicy#retryable?` (DESIGN.md §6.7). **Until 2026-08-23 nothing consulted the policy at all** — it was built, validated, documented as a `retry:` option and never called, so `Retry-After` was honoured nowhere. If you touch the middleware, keep the method check in the policy rather than the middleware: one place decides. **Sole ledgered exception:** the opt-in `21470` key-rotation remediation in `Crypto::PublicKeys#with_key_rotation`, where the request was declined outright so nothing happened server-side and the retry carries a *different* key (`docs/REFERENCE.md` §10.2). Not a precedent for anything else.
- Honour `Retry-After` unclamped. Retrying sooner than instructed lengthens the block, and KSeF treats rotating IPs to dodge a 429 as an abuse pattern.
- No secrets in code, logs, fixtures, or VCR cassettes — scrub filters per DESIGN.md §4.5.
- No new runtime dependency beyond the four in DESIGN.md §4.3 (`faraday`, `nokogiri`, `bigdecimal`, `zeitwerk`) without asking. Excluded: `base64`, `logger`/`ostruct` requires, `jwt`, `activesupport`, `dry-*`, `rexml`. `rubyzip` is deferred to 0.2, not permanently banned.
- **Two upstream traps that only bite at runtime. Both now have code**, so these are maintenance rules rather than warnings about future work. `docs/REFERENCE.md` §14.1: the AES IV is a discrete request field, *not* a prefix on the ciphertext, whatever `sesja-interaktywna.md` says — the prose version yields payloads KSeF cannot decrypt; implemented in `Crypto::Encryptor`. §14.2: `downloadUrl` is a pre-signed storage link — follow it as an opaque URI, **never send the bearer token to it**, and verify `x-ms-meta-hash`; implemented in `UPO::Client`, which routes those requests over `HTTP::Connection.storage` — a connection with no bearer and no base URL, so the rule cannot be broken rather than merely being remembered (§12.3). **Do not "simplify" that into the main connection.** `spec/openapi_contract_spec.rb` guards both against the contract; read the ledger before changing either.
- No `Float` anywhere money flows — `BigDecimal` only.
- `required_ruby_version` stays `">= 3.2.0"` — no upper bound, ever.
- Do not commit `Gemfile.lock` (library convention; CI resolves per matrix Ruby).

## Conventions

- Ruby floor is 3.2: no `it` block parameter, no 3.3+/4.0-only syntax **and no post-3.2 APIs**. RuboCop only half-covers this — see the floor section above.
- `# frozen_string_literal: true` in every file. `Data.define` for value objects. `pack("m0")` / `unpack1("m0")` for base64.
- Always pass `encoding: "UTF-8"` to `File.read`. The ambient locale is not UTF-8, and every KSeF artifact contains Polish characters.
- **Where a pinned schema lives is a licensing decision, not a layout one.** `lib/` only for the Ministry's own documents (FA(3), auth, UPO — MIT, so redistributable) *and* only when something at runtime reads them, **or will within the current milestone** — the UPO schema was pinned ahead of its consumer under that amendment, and `UPO::Validator` now reads it at runtime, so the rule's plain form applies again (`docs/REFERENCE.md` §1.3 records the precedent for the next time). Third-party schemas it merely redistributes (W3C xmldsig, ETSI XAdES, OASIS UBL) go in `spec/fixtures/` and are not packaged: MF's licence cannot relicense someone else's document. `docs/REFERENCE.md` §1.2 has the test to apply; moving one into `lib/` is a question for the human (DESIGN.md §12).
- Every behavior change lands with specs. FA(3) serializer changes land with golden-file updates, and goldens must validate against the pinned XSD.
- Coverage is gated on **line 99, branch 95, method 100** (`generated/` excluded). **Re-ratchet these at each phase boundary, not once** — they are percentages, so the absolute number of untested branches they permit grows as the codebase does; Phase 2 roughly doubles it. Part of the phase definition of done. The floors ratchet — raise them when the real numbers improve, never lower one to make a change pass. `method: 100` is the one that bites: a method nothing exercises fails the build. Branch coverage is where real gaps hide, so a change that adds a conditional needs a test per path, not just per line. Filtered runs (single file, `--tag`) skip the gate by design.
- Thread safety of `Ksef::Client` is a requirement (DESIGN.md §5.2), not an optimization — and it is now shipped and spec-covered: frozen config, stateless connections, one mutex round the memoised credential, no session held on the client. A spec drives six concurrent sends and asserts a single authentication.

## Workflow

- Work the current milestone only (see Status); do not start the next phase early.
- Definition of done: `bundle exec rake` green — pinned artifacts verified, codegen reproducible, specs passing **with the coverage floors enforced**, RuboCop clean. That task list mirrors CI, so a green `rake` means a green matrix leg.

  It did not, until 2026-08-23. `rake spec` invokes `rspec --pattern spec/**{,/*/**}/*_spec.rb`, and that pattern *value* starts with `spec/` — which `spec_helper`'s filtered-run check read as "the user narrowed the run", so it skipped the coverage gate on **every** `rake`. CI calls `bundle exec rspec` directly and was always strict, so the documented definition of done was weaker than the thing it claimed to mirror. Fixed by stripping `--pattern` and its value before looking for selectors.
- Unsure how KSeF behaves? Read the official C#/Java clients (github.com/CIRFMF) before guessing, then ledger the finding in `docs/REFERENCE.md`.
- **Open** DESIGN.md §12 decisions belong to the human — ask, don't pick. Already settled, so don't re-ask: **DESIGN.md §12 item 2** XSD redistribution (schemas are MIT-licensed → bundled; `docs/REFERENCE.md` §1.2), **§12 item 1** author/repo metadata (Tibor Molnár, `tibor@timcraft.pl`, `github.com/tibortc/ksef_client`), and the 3.2 floor surviving its EOL (DESIGN.md §3).
