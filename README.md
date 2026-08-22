# ksef_client

[![test](https://github.com/tibortc/ksef_client/actions/workflows/test.yml/badge.svg)](https://github.com/tibortc/ksef_client/actions/workflows/test.yml)
[![Coverage Status](https://coveralls.io/repos/github/tibortc/ksef_client/badge.svg?branch=main)](https://coveralls.io/github/tibortc/ksef_client?branch=main)

Ruby client for **KSeF 2.0**, Poland's national e-invoicing system (Krajowy System
e-Faktur), with a standalone **FA(3)** invoice builder.

Invoicing through KSeF has been a legal obligation since 2026-02-01 for taxpayers with
2024 gross sales above 200M PLN, and since 2026-04-01 for essentially everyone else. The
Ministry of Finance publishes official SDKs in C# and Java, but none for Ruby.

**How this differs from [`ksef-rb`](https://github.com/skycocker/ksef-rb).** That gem is a
working KSeF 2.0 client and is further along on transport; if you already generate FA(3)
XML yourself, it may be all you need. `ksef_client` aims at the other half of the problem:
**authoring and validating** the invoice document — a schema-backed builder for all seven
invoice types, the FA(3) XSD bundled, and three tiers of validation before anything is
submitted.

> **Status: pre-release, under active development.**
>
> **Working:** the transport foundations (configuration, environments, error model, HTTP
> layer), the FA(3) schema metadata, offline XSD validation, and building a plain `VAT`
> invoice — via the `Ksef::FA3.build` DSL or the value objects directly — to schema-valid
> XML.
>
> **Not yet:** authentication, encryption, sessions — so nothing can actually be *sent* to
> KSeF yet — and the other six invoice types. See [Roadmap](#roadmap).
>
> In the quickstart below, **everything up to and including `Ksef::FA3.build` runs
> today**; the `client` calls do not exist yet.

## Installation

```ruby
gem "ksef_client"
```

The gem is named `ksef_client`; the namespace is `Ksef`.

```ruby
require "ksef_client"   # defines Ksef, Ksef::Client, Ksef::FA3, ...
```

## Quickstart

The `Ksef::FA3.build` block runs today and produces schema-valid FA(3) XML. The `client`
calls around it are the target API for 0.1.0 and are **not implemented yet**.

```ruby
client = Ksef::Client.new(                       # ← not yet
  env:  :test,
  auth: Ksef::Auth::Token.new(context_nip: "9999999999", token: ENV["KSEF_TOKEN"])
)

invoice = Ksef::FA3.build do |f|                 # ← this part works
  f.seller nip: "9999999999", name: "ACME sp. z o.o.",
           address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001", country: "PL" }
  f.buyer  nip: "1111111111", name: "Klient S.A.",
           address: { street: "Długa 2", city: "Kraków", postal_code: "30-001", country: "PL" }
  f.number "FV/2026/08/001"
  f.issue_date Date.today
  f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23"
end

invoice.validate!                              # ← works: offline, against the bundled XSD
invoice.to_xml                                 # ← works

result = client.send_invoice(invoice)          # ← not yet: validate! → encrypt → submit
status = client.wait_until_accepted(result.reference)
status.ksef_number                             # => "9999999999-20260822-…-AF"
upo    = client.upo(result.reference)          # signed UPO XML — archive this verbatim
```

The DSL accepts English shorthand (`qty:`, `vat:`) and coerces a plain Hash into an
address. A misspelled key raises and tells you what was permitted, rather than quietly
producing an invoice with a field missing:

```ruby
Ksef::FA3.build { |f| f.line name: "X", price: 1 }
# => Ksef::ValidationError: Unknown line option(s) :price. Permitted: name, quantity,
#    unit, net_unit_price, vat_rate, net_amount. Shorthand: qty for quantity, vat for vat_rate
```

`address:` takes an `Address`, a Hash of its fields, or an already-formatted string —
FA(3) stores an address as free text, so all three end up in the same place.

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

### Building an invoice without the DSL

The DSL is a thin front end over plain value objects, and they are public API too. Reach
for these when you are mapping from your own domain objects and the keyword block would
just be indirection.

```ruby
require "ksef_client"

seller = Ksef::FA3::Subject.new(
  nip: "9999999999", name: "ACME sp. z o.o.",
  address: Ksef::FA3::Address.new(street: "Prosta 1", city: "Warszawa", postal_code: "00-001")
)
buyer = Ksef::FA3::Subject.new(
  nip: "1111111111", name: "Klient S.A.",
  address: Ksef::FA3::Address.new(street: "Długa 2", city: "Kraków", postal_code: "30-001")
)

invoice = Ksef::FA3::Invoice.new(
  seller: seller, buyer: buyer,
  number: "FV/2026/08/001",
  issue_date: Date.new(2026, 8, 22),
  lines: [
    Ksef::FA3::Line.new(name: "Consulting", quantity: 10, unit: "godz.",
                        net_unit_price: BigDecimal("150"), vat_rate: "23")
  ]
)

invoice.net_total    # => 1500
invoice.vat_total    # => 345
invoice.gross_total  # => 1845

invoice.validate!    # against the bundled XSD, no network
invoice.to_xml       # => "<?xml version=\"1.0\" encoding=\"UTF-8\"?>..."
```

Three things it does for you that the schema requires but you would not think to supply:
the buyer's mandatory `JST` and `GV` flags, the five mandatory `Adnotacje` flags, and one
branch of each mandatory choice wrapper. Omitting any of them is a schema error.

Rounding is explicit, because Polish VAT law permits two approaches and they can differ by
a grosz — pass `rounding: :per_line` (the default) or `:per_summary`.

### Querying the schema

The FA(3) schema metadata is generated from the bundled XSD, so element ordering and
enum membership are queryable without parsing anything yourself:

```ruby
E = Ksef::FA3::Generated::Enums
E.values_for("TRodzajFaktury")      # => ["VAT", "KOR", "ZAL", "ROZ", "UPR", "KOR_ZAL", "KOR_ROZ"]
E.valid?("TStawkaPodatku", "23")    # => true

T = Ksef::FA3::Generated::Types
T.ordered_elements("Faktura").map { |e| e[:name] }
# => ["Naglowek", "Podmiot1", "Podmiot2", ...] — the order KSeF requires
```

Note VAT rate codes are **strings**, not numbers: half of the fourteen are codes like
`"0 WDT"`, `"zw"` and `"np I"`.

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
| 0.1.0 | **Both auth methods** — certificate/XAdES *and* KSeF token — crypto, online sessions, send/status/UPO/download, full FA(3) builder for all seven invoice types |
| 0.2 | Batch sessions, invoice query/search, package export, hardened error catalogue |
| 0.3 | KSeF certificate lifecycle endpoints, permissions API, offline QR codes |
| 1.0 | After sustained production use; API stability promise begins |

Certificate authentication is in 0.1 rather than deferred, because a KSeF token can only
be issued *after* a one-time authentication with a qualified signature — so a token-only
client cannot get you started from nothing.

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
