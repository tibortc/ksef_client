# ksef_client — agent instructions

Read DESIGN.md fully before writing any code; follow its §0. It is the spec; this file is the cheat sheet.

Precedence when sources disagree: **pinned artifacts** (OpenAPI spec, FA(3) XSD) > `docs/REFERENCE.md` > DESIGN.md > this file > memory. The ledger is *derived* from the artifacts, so where it contradicts them the artifacts win and the ledger gets corrected (DESIGN.md §2).

## Status

- Current milestone: **Phase 2** (DESIGN.md §11). Phase 1 is complete — all three "Done when" gates pass: codegen reproducible, VAT golden file XSD-valid, CI matrix green.
- Phase 2, in order: **certificate/XAdES auth first** (it is what lets the gem mint its own KSeF token, and it unblocks §12.4), then the crypto module with golden vectors, then online sessions, then the remaining six invoice types starting with KOR (§7.4).
- Known gaps carried into Phase 2: `Ksef::FA3.build` — the DSL in DESIGN.md §8 — is not implemented; only keyword-arg constructors exist. §8 must run verbatim before 0.1.0 ships (§0.4). `docs/field_mapping.md` is deferred (see DESIGN.md §7.2).

## Commands

Every command below needs this prelude first:

```bash
export PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8
```

rbenv's shims are not on `PATH` in a non-interactive shell — without the prefix, `bundle` resolves to macOS system Ruby 2.6.10 and dies. Without `LANG`, `File.read`/`JSON.parse` raise `Encoding::InvalidByteSequenceError` on the Polish text that pervades the KSeF specs and schemas.

- `bundle exec rake` — **the one to reach for.** Runs `verify:artifacts`, `spec`, `rubocop`. This is the definition of done.
- `bundle exec rake verify:artifacts` — check pinned artifacts against `docs/artifacts.sha256`. A failure means **upstream changed**: investigate and ledger it, never "repair" the checkout.
- `bundle exec rspec` — unit + golden tests. Must never touch the network; `spec_helper` enforces that via WebMock.
- `bundle exec rspec spec/ksef/configuration_spec.rb:42` — single example while iterating.
- `bundle exec rubocop` — style authority. Not done until clean; prefer fixing over disabling cops.
- `KSEF_ENV=test bundle exec rspec --tag integration` — live TEST suite (needs `KSEF_TEST_NIP`, `KSEF_TEST_TOKEN`). Run only when explicitly asked; it is nightly-CI's job. Tag-based, matching `nightly.yml`. No spec carries the tag yet, and integration specs must opt back into the network access `spec_helper` disables.
- `KSEF_RELEASE_CHECK=1 bundle exec rspec` — adds the release gates in `spec/release_readiness_spec.rb`: gemspec invariants, the four approved runtime deps, and no reintroduced metadata placeholders. **Currently green — keep it that way.**

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

Last verified green on 3.2.11: 117 examples, 0 failures, RuboCop clean, gem builds.

Even so, when reaching for any core or stdlib method, confirm it exists in 3.2 rather than assuming — a filtered local run will not catch it.

> **Settled 2026-08-22 — do not re-raise.** Ruby 3.2 is EOL, and it stays the floor anyway. The version-support policy's EOL-drop rule governs future series (3.3 onward), not this floor; the reasoning is in DESIGN.md §3. Do not propose raising the floor to 3.3, and do not treat 3.2's EOL as licence to use post-3.2 APIs.

## Hard rules — violating any of these means stop and flag

- Never invent KSeF endpoint paths, XML element names, namespace URIs, or crypto parameters. Verify against the pinned OpenAPI spec / XSD / CIRFMF docs and record value + source + date in `docs/REFERENCE.md` first.
- Never target the PROD environment from any test or script. Integration code must hard-fail on `KSEF_ENV=prod`.
- **Only GET and HEAD are ever auto-retried.** Every POST/PUT/PATCH/DELETE surfaces its error to the caller — a duplicate invoice in KSeF is a real tax problem. See `Ksef::RetryPolicy` and DESIGN.md §6.7.
- Honour `Retry-After` unclamped. Retrying sooner than instructed lengthens the block, and KSeF treats rotating IPs to dodge a 429 as an abuse pattern.
- No secrets in code, logs, fixtures, or VCR cassettes — scrub filters per DESIGN.md §4.5.
- No new runtime dependency beyond the four in DESIGN.md §4.3 (`faraday`, `nokogiri`, `bigdecimal`, `zeitwerk`) without asking. Excluded: `base64`, `logger`/`ostruct` requires, `jwt`, `activesupport`, `dry-*`, `rexml`. `rubyzip` is deferred to 0.2, not permanently banned.
- No `Float` anywhere money flows — `BigDecimal` only.
- `required_ruby_version` stays `">= 3.2.0"` — no upper bound, ever.
- Do not commit `Gemfile.lock` (library convention; CI resolves per matrix Ruby).

## Conventions

- Ruby floor is 3.2: no `it` block parameter, no 3.3+/4.0-only syntax **and no post-3.2 APIs**. RuboCop only half-covers this — see the floor section above.
- `# frozen_string_literal: true` in every file. `Data.define` for value objects. `pack("m0")` / `unpack1("m0")` for base64.
- Always pass `encoding: "UTF-8"` to `File.read`. The ambient locale is not UTF-8, and every KSeF artifact contains Polish characters.
- Every behavior change lands with specs. FA(3) serializer changes land with golden-file updates, and goldens must validate against the pinned XSD.
- Coverage is gated on **line 95, branch 90, method 100** (`generated/` excluded). The floors ratchet — raise them when the real numbers improve, never lower one to make a change pass. `method: 100` is the one that bites: a method nothing exercises fails the build. Branch coverage is where real gaps hide, so a change that adds a conditional needs a test per path, not just per line. Filtered runs (single file, `--tag`) skip the gate by design.
- Thread safety of `Ksef::Client` is a requirement (DESIGN.md §5.2), not an optimization. (`Ksef::Client` is not written yet.)

## Workflow

- Work the current milestone only (see Status); do not start the next phase early.
- Definition of done: `bundle exec rake` green — pinned artifacts verified, codegen reproducible, specs passing, RuboCop clean. That task list mirrors CI exactly, so a green `rake` means a green matrix leg.
- Unsure how KSeF behaves? Read the official C#/Java clients (github.com/CIRFMF) before guessing, then ledger the finding in `docs/REFERENCE.md`.
- **Open** DESIGN.md §12 decisions belong to the human — ask, don't pick. Already settled, so don't re-ask: **§12.2** XSD redistribution (schemas are MIT-licensed → bundled; `docs/REFERENCE.md` §1.2), **§12.1** author/repo metadata (Tibor Molnár, `tibor@timcraft.pl`, `github.com/tibortc/ksef_client`), and the 3.2 floor surviving its EOL (DESIGN.md §3).
