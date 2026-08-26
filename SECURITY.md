# Security policy

## Reporting a vulnerability

Please report security issues privately via GitHub's "Report a vulnerability" flow on
this repository, rather than opening a public issue. You can expect an acknowledgement
within a few working days.

This gem handles credentials that authenticate against a tax authority, and invoice
payloads that are legally binding documents. Reports about credential leakage, weakened
TLS, or incorrect cryptographic parameters are treated as high severity.

## Supported versions

Security fixes land on the latest minor release.

The supported interpreter range is whatever `required_ruby_version` declares — currently
**MRI >= 3.2**. Note that this **includes Ruby 3.2 even though 3.2 is EOL upstream**: the
floor is a deliberate commitment (see DESIGN.md §3), so 3.2 users do receive fixes from
this gem.

That said, an EOL interpreter stops receiving fixes for CVEs *in Ruby itself*, which this
project cannot patch. If you are on 3.2 for compliance reasons, upgrading Ruby is still
the stronger position.

Once a series does fall below the floor in a future minor release, `required_ruby_version`
resolves at install time, so users on that interpreter stay on the last compatible release
and stop receiving fixes from us.

## Handling of secrets

The following must never appear in logs, `#inspect` output, exception messages, or test
fixtures:

- KSeF tokens and JWTs (access and refresh)
- Session symmetric keys and IVs
- Full invoice payloads at default log level

Enforced by:

- A redacting `#inspect` on configuration and authentication objects.
- `spec/cassette_hygiene_spec.rb`, which scans every committed VCR cassette for `Bearer `
  headers and for any value this machine holds in `KSEF_TEST_TOKEN`. **Not the NIP**: a tax
  identifier is printed on every invoice and is embedded in the KSeF number itself, so
  redacting it corrupts the very documents a cassette exists to hold — and costs the two
  checks only a real response can support, the KSeF number's checksum and KSeF's own
  integrity header. The token is the credential.

  It also scans for anything shaped like a **JSON Web Token**, added 2026-08-26 after a
  recording carried a live refresh token past both of the other checks: it was in a JSON
  response body, so it was neither a `Bearer ` header nor a value this machine held in its
  environment. Scanning for the shape of a credential catches the ones you did not predict. It
  finds cassettes by content, not by path, so one saved somewhere unconventional is still
  scanned. **No cassette exists yet** — the harness landed on 2026-08-26 but nothing has been
  recorded — so the check still passes vacuously. The scrubbing hooks it depends on are in
  `spec/support/vcr.rb`, written before the first recording rather than after, because a
  cassette committed without them is a leak `git` remembers.
- Integration tests reading credentials only from environment variables
  (`KSEF_TEST_NIP`, `KSEF_TEST_TOKEN`, `KSEF_ENV=test`).

## Transport security

- TLS verification is always on. No code path may set `VERIFY_NONE`; there is no
  configuration option to disable it.
- Minimum TLS version is 1.2.

## Testing against production

The test suite aborts if `KSEF_ENV=prod`, and the nightly workflow fails the same way.
Never point automated tests at the production environment — invoices submitted there have
full legal force.

## Rate limits

KSeF records and analyses rate-limit breaches, and explicitly treats spreading one
context across many IP addresses as an abuse pattern. This client honours `Retry-After`
and will never work around a 429 by rotating connections. Please do not add such a
mechanism.

## Publishing

Releases use RubyGems Trusted Publishing (OIDC). No long-lived RubyGems API key exists
for this project. The gemspec sets `rubygems_mfa_required`.
