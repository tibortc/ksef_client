# Contributing

## Getting set up

```bash
bin/setup            # bundle install + verify pinned artifacts
bundle exec rake     # verify:artifacts, specs, RuboCop
```

Development targets the current Ruby 4.0 patch (see `.ruby-version`) because the
strictest interpreter surfaces un-bundled-stdlib and deprecation issues locally. The
library itself supports MRI >= 3.2.

## The one rule that matters most

**Never invent an endpoint path, XML element name, namespace URI, or cryptographic
parameter.**

This gem talks to a tax authority. A plausible-looking guess that happens to be wrong
produces rejected invoices, or worse, silently malformed ones. So:

1. Every externally sourced fact goes in [`docs/REFERENCE.md`](docs/REFERENCE.md) with its
   value, source URL and retrieval date, *before* the code depending on it is written.
2. The authoritative sources, **in precedence order**: the pinned OpenAPI spec, the pinned
   FA(3) XSD, then `CIRFMF/ksef-api`'s prose, then the integrator documentation portal. This
   order is the opposite of what an earlier version of this list said, and it is not a
   preference — the ledger records four occasions where upstream prose contradicted the
   contract and the contract was right (`docs/REFERENCE.md` §4.8, §11.3, §12.1, §13.1). Read
   the schema for a field before trusting a sentence about it.
3. If a detail is not in the ledger and not verifiable from those sources, **stop and ask**
   rather than guessing.
4. When the pinned artifacts and the design document disagree, the artifacts win. Update
   the ledger and note the divergence in your PR description.

## Pinned artifacts

`spec/fixtures/openapi/open-api.json` and `lib/ksef/fa3/schema/**` are verbatim upstream
copies, checksummed in `docs/artifacts.sha256`. Do not edit them, not even whitespace.

If `rake verify:artifacts` fails, upstream changed. That is a finding to investigate and
ledger, not a checkout to repair. Refresh the files, update the manifest and the ledger,
and describe the behavioural impact in your PR.

## Constraints that are decided, not open

Please raise these for discussion rather than changing them in a PR:

- **Runtime dependencies are exactly four**: `faraday`, `nokogiri`, `bigdecimal`,
  `zeitwerk`. A fifth needs a discussion first.
- **No upper bound on `required_ruby_version`**, ever.
- **The Ruby 3.2 floor stays**, despite 3.2 being EOL upstream — see DESIGN.md §3. Please
  don't open a PR raising it, and don't reach for a 3.3+ API on the grounds that 3.2 is
  past EOL.
- **`BigDecimal` for every monetary amount.** `Float` is forbidden in any monetary path.
- **Invoice submission is never auto-retried.**
- **No `VERIFY_NONE`**, no way to disable TLS verification.
- `lib/ksef/fa3/generated/` is codegen output — regenerate with `rake fa3:generate`, never
  hand-edit.

## Style

- `# frozen_string_literal: true` in every file.
- `Data.define` for immutable value and response objects.
- UTF-8 throughout; XML serialised with an explicit `encoding="UTF-8"` declaration. Note
  that file reads need an explicit encoding, since a non-UTF-8 locale otherwise yields
  US-ASCII strings and breaks on Polish characters.
- No `RUBY_VERSION` string surgery.
- RuboCop enforces what it can; `bundle exec rubocop -a` for the mechanical parts.

## Tests

| Tier | Runs |
|---|---|
| Unit (WebMock stubs; VCR planned, no cassette yet) | every push, full Ruby matrix |
| Golden files, round-trip, crypto vectors | every push |
| Live TEST integration | nightly and pre-release only, never per-PR |

Coverage is gated on three criteria, excluding `generated/`: **line 99, branch 97,
method 100**. `spec/spec_helper.rb` is the single source of truth for these numbers —
if this paragraph and that file ever disagree, the file wins. Branch coverage is the one that finds real gaps — the suite once sat at 99%
line coverage with 83% branch coverage, meaning plenty of conditional paths were untested
behind covered lines. Method coverage at 100 means a method nothing exercises fails the
build.

The floors only ever move up, and they move **at phase boundaries** — set with
deliberate margin under the then-current actuals, never pinned to them. Don't lower one to make
a change pass. If you hit the method floor, the usual cause is a new method reachable only
from an untested branch. Filtered runs (a single file, or `--tag`) skip the gate, since
they legitimately cover less.

Live integration specs are tagged
`:integration` and read credentials only from `KSEF_TEST_NIP` / `KSEF_TEST_TOKEN` with
`KSEF_ENV=test`.

Never point tests at production. The suite aborts on `KSEF_ENV=prod`.

Cassettes must be scrubbed of tokens, JWTs and keys before committing.

## Releasing

1. Confirm no metadata placeholders were reintroduced: `grep -r UNRESOLVED-DESIGN-12-1`.
   The release gate checks this too, but it is cheaper to notice here.
2. Update `CHANGELOG.md`, including the KSeF API version and FA schema revision targeted.
3. Confirm a **green nightly on the release commit**.
4. Do one deliberate local full-suite run on **Ruby 3.2** — the floor contract deserves a
   look, not just a matrix tick. RuboCop cannot substitute for this: `TargetRubyVersion`
   catches incompatible *syntax* but not post-3.2 *APIs*, so a method added in 3.3 or 3.4
   passes lint and then `NoMethodError`s on a user's interpreter.

   ```bash
   mv Gemfile.lock /tmp/Gemfile.lock.dev
   BUNDLE_PATH=/tmp/ksef-bundle-32 RBENV_VERSION=3.2.11 bundle install
   BUNDLE_PATH=/tmp/ksef-bundle-32 RBENV_VERSION=3.2.11 bundle exec rake
   mv /tmp/Gemfile.lock.dev Gemfile.lock
   ```

   The separate `BUNDLE_PATH` leaves your development gem set alone, and resolving without
   the lockfile mirrors CI. Bundler on 3.2 cannot read a lockfile written by Bundler 4.
5. Tag `vX.Y.Z`. The release workflow runs the suite with `KSEF_RELEASE_CHECK=1`, checks
   the tag against `Ksef::VERSION`, and publishes via Trusted Publishing.
