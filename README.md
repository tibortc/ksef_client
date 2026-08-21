# ksef_client

Ruby client for **KSeF 2.0**, Poland's national e-invoicing system (Krajowy System
e-Faktur), with a standalone **FA(3)** invoice builder.

Invoicing through KSeF has been a legal obligation since 2026-02-01 for taxpayers with
2024 gross sales above 200M PLN, and since 2026-04-01 for essentially everyone else. The
Ministry of Finance publishes official SDKs in C# and Java; this gem fills the Ruby gap.

> **Status: pre-release, under active development.** The transport foundations
> (configuration, environments, error model, HTTP layer) are in place. Authentication,
> encryption, sessions and the FA(3) builder are not implemented yet — see
> [Roadmap](#roadmap). The quickstart below is the **target** API for 0.1.0 and does not
> run today.

## Installation

```ruby
gem "ksef_client"
```

The gem is named `ksef_client`; the namespace is `Ksef`.

```ruby
require "ksef_client"   # defines Ksef, Ksef::Client, Ksef::FA3, ...
```

## Quickstart (target API for 0.1.0 — not yet functional)

```ruby
client = Ksef::Client.new(
  env:  :test,
  auth: Ksef::Auth::Token.new(context_nip: "9999999999", token: ENV["KSEF_TOKEN"])
)

invoice = Ksef::FA3.build do |f|
  f.seller nip: "9999999999", name: "ACME sp. z o.o.",
           address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
  f.buyer  nip: "1111111111", name: "Klient S.A.",
           address: { street: "Długa 2", city: "Kraków", postal_code: "30-001", country: "PL" }
  f.number "FV/2026/08/001"
  f.issue_date Date.today
  f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23"
end

result = client.send_invoice(invoice)          # validate! → encrypt → session → submit
status = client.wait_until_accepted(result.reference)
status.ksef_number                             # => "9999999999-2026…"
upo    = client.upo(result.reference)          # signed UPO XML — archive this verbatim
```

## What works today

```ruby
config = Ksef::Configuration.new(env: :test, timeout: { read: 120 })
config.base_url        # => "https://api-test.ksef.mf.gov.pl/v2"
config.inspect         # credentials are redacted, never logged

conn = Ksef::HTTP::Connection.build(config)
conn.get("rate-limits")
```

Errors from the API arrive as a typed hierarchy carrying the Ministry's own diagnostics:

```ruby
begin
  conn.get("sessions")
rescue Ksef::RateLimitedError => e
  e.retry_after      # => 30 — seconds, from the Retry-After header. Honour it.
rescue Ksef::AuthorizationError => e
  e.reason_code      # => "missing-permissions"
  e.security         # => {"requiredAnyOfPermissions" => ["InvoiceWrite"], ...}
rescue Ksef::ApiError => e
  e.status           # => 400
  e.code             # => 21405
  e.details          # => ["Wskazany kod formularza nie jest wspierany."]
  e.trace_id         # quote this to Ministry support
end
```

## Environments

| Env | Base URL |
|---|---|
| `:test` | `https://api-test.ksef.mf.gov.pl/v2` |
| `:demo` | `https://api-demo.ksef.mf.gov.pl/v2` |
| `:prod` | `https://api.ksef.mf.gov.pl/v2` |

Each URL was verified against that environment's own OpenAPI document; see
[`docs/REFERENCE.md`](docs/REFERENCE.md). Note the base URL already includes `/v2`.
`Ksef::Environments.custom(base_url:)` is available for non-public deployments.

TEST and DEMO are for integration testing only — never send real invoices or real
taxpayer data to them, and use random NIPs. TEST data is not isolated between
integrators.

## Ruby support

- **MRI >= 3.2**, with **no upper bound, ever.** `required_ruby_version` resolves at
  install time, so an upper bound strands users on each new Ruby release.
- CI covers 3.2, 3.3, 3.4, 4.0 and `head`, and the full suite is run on 3.2 at every
  milestone — the floor is verified, not just declared.
- **The 3.2 floor is a commitment, not a default.** Ruby 3.2 is EOL upstream, and this gem
  still supports it deliberately: Polish tax-compliance software upgrades slowly, and 3.2
  is the Rails 8.0 floor. There is no plan to raise it.
- Later EOL series will be dropped in **minor** releases with a changelog note. Because
  version constraints resolve at install time, users on an older Ruby keep receiving the
  last compatible release.
- **MRI only.** JRuby and TruffleRuby are untested — the crypto layer needs precise
  OpenSSL RSA-OAEP parameterisation. PRs welcome.

## Design notes

- **Two decoupled subsystems.** The FA(3) builder has no HTTP dependency and is usable on
  its own; the transport layer accepts anything responding to `#to_xml`, or a raw XML
  string.
- **`BigDecimal` everywhere for money.** `Float` is forbidden in any monetary path.
- **Invoice submission is never auto-retried.** A duplicate invoice in KSeF is a real tax
  problem. Idempotent GETs retry with backoff; a failed submission surfaces to you.
- **Thread-safe.** A single client is shareable across threads (Sidekiq is the expected
  habitat); configuration is frozen at construction.
- **Secrets never logged.** Tokens, JWTs, symmetric keys and IVs are redacted from
  `#inspect` output.

## Roadmap

| Version | Scope |
|---|---|
| 0.1.0 | KSeF-token auth, crypto, online sessions, send/status/UPO/download, full FA(3) builder for all seven invoice types |
| 0.2 | Batch sessions, invoice query/search, package export, hardened error catalogue |
| 0.3 | XAdES authentication, certificate lifecycle, permissions API, offline QR codes |
| 1.0 | After sustained production use; API stability promise begins |

## Development

```bash
bin/setup            # or: bundle install
bundle exec rake     # verify pinned artifacts, specs, RuboCop
```

Every externally sourced fact — endpoint paths, XML element names, namespace URIs,
crypto parameters — is recorded with its source and retrieval date in
[`docs/REFERENCE.md`](docs/REFERENCE.md). Nothing enters the code without an entry there.

## Licence

MIT. The bundled FA(3) schemas are published by Ministerstwo Finansów, also under MIT;
see `lib/ksef/fa3/schema/LICENSE.upstream.txt`.

This project is not affiliated with or endorsed by the Polish Ministry of Finance.
