# Changelog

All notable changes to this project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Every release entry states the **KSeF API version** and **FA schema revision** it
targets. The Ministry ships changes continuously, so users must be able to answer "which
gem version for which API state".

## [Unreleased]

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
