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
> **Certificate authentication works, against the real TEST environment.** The
> `AuthTokenRequest` document, its XAdES-BES signature and the five HTTP calls that flow
> needs are implemented, and this gem has minted a KSeF token end to end with no external client.
>
> **Both authentication methods are now implemented**, along with the encryption layer they
> and the session layer share: `Ksef::Crypto` fetches and selects the Ministry's published
> keys, wraps a symmetric key with RSA-OAEP, and encrypts payloads with AES-256-CBC.
>
> **The session layer works** too: `Ksef::Sessions::Online` opens a session, encrypts and
> submits invoices, and closes it; `Ksef::Sessions::Status` reads and waits on session and
> per-invoice status.
>
> **UPO retrieval works** as well, over a connection deliberately built without a
> credential: the download links are third-party storage URIs, so the access token must
> never reach them.
>
> **`Ksef::Client` ties it together, and the quickstart below is now real code** — a spec
> drives that exact snippet end to end, from `Ksef::FA3.build` through `send_invoice`,
> `wait_until_accepted` and `upo`.
>
> **It has now run against the real thing.** On 2026-08-24 the nightly opened a session on
> KSeF TEST, encrypted and submitted an invoice this gem built, had it **accepted**, got a
> KSeF number whose checksum our own code agrees with, and retrieved the signed UPO with its
> bytes matching the hash the server published.
>
> **The honest caveat, narrowed:** what remains stub-only is token refresh, the KSeF-token
> auth call, invoice download and anything batch. Those are still "believed correct" rather
> than proven.
>
> **Reading invoices back works** — `Ksef::FA3.parse` turns FA(3) XML into the same model the
> builder produces, tested against the Ministry's own published sample invoices. It refuses
> what it cannot represent faithfully rather than guessing.
>
> **Validation runs in three stages now**, not one: the model (required fields, enum
> membership, NIP checksums, string lengths, date sanity), the serialized bytes (valid UTF-8,
> no BOM, no processing instructions, UTF-8 prolog, no characters KSeF refuses, size), then the
> XSD. Those are validator tiers 1a, 1b and 2 — tier 3, the business rules, is still absent.
> `invoice.errors` reports the model problems together, each addressed to the field that
> caused it (`lines[2].vat_rate`); the byte and schema checks run once the model is sound, and
> report against `document` and `schema`.
>
> **Corrections build and parse.** `KOR` carries what it corrects — one invoice or fifty
> thousand — the reason, the effect date, the previous state of a party, and rows marked
> before/after. Its tax summary is *stated* rather than derived, because a correction's
> buckets are deltas its rows need not determine: three of the Ministry's five worked
> corrections have no usable rows at all.
>
> **Advance invoices work too.** A `ZAL` carries the order or contract it collects against
> (`Zamowienie`) and has no invoice rows at all; a `ROZ` names every advance invoice it settles
> and states what is left to pay.
>
> **Not yet:** validator tier 3 — the reconciliation rules — and three of the seven invoice
> types: `VAT`, `KOR`, `ZAL` and `ROZ` build and parse; `UPR` and the two remaining `KOR_`
> combinations do not. See [Roadmap](#roadmap).

## Installation

**0.1.0 is not released yet.** Only `0.1.0.rc1` is on RubyGems — a name-claiming
placeholder that deliberately contains none of the API below — and Bundler will not select a
prerelease for an unconstrained requirement, so `gem "ksef_client"` fails outright. Until
0.1.0 ships, install from git:

```ruby
gem "ksef_client", github: "tibortc/ksef_client"
```

After release, the usual line will work:

```ruby
gem "ksef_client"   # once 0.1.0 is published
```

The gem is named `ksef_client`; the namespace is `Ksef`.

```ruby
require "ksef_client"   # defines Ksef, Ksef::FA3, Ksef::Auth, Ksef::Crypto, ...
```

## Quickstart

All of this runs. `spec/ksef/client_spec.rb` drives the same sequence against stubbed HTTP, so
an API change here breaks a test — though the snippet is mirrored by hand rather than
extracted, so the *prose* can still drift from the spec. And see the status note above on what
stubs do and do not prove.

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

invoice.validate!                              # offline: model, bytes, then the XSD
invoice.to_xml

result = client.send_invoice(invoice)          # validate! → encrypt → session → submit
status = client.wait_until_accepted(result.reference)
status.ksef_number                             # => "9999999999-20260823-…-3F"
upo    = client.upo(result.reference)          # signed UPO — archive the bytes verbatim
Dir.mkdir("upo") unless Dir.exist?("upo")      # #write does not create directories
upo.write("upo/#{status.ksef_number}.xml")     # binwrite: the MF signature covers octets
```

`send_invoice` opens a session of its own, submits, and closes it. Sending many invoices?
Use a block, so they share one session instead of opening thirty:

```ruby
receipts = client.session do |batch|
  invoices.map { |invoice| batch.send_invoice(invoice) }
end                                            # ← closed here, which starts the collective UPO
```

`result.reference` is the pair of references — session and invoice — because every status
and UPO endpoint is keyed on both. That is why it can be passed straight to
`wait_until_accepted` and `upo`.

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

Errors from the API arrive as a typed hierarchy carrying the Ministry's own diagnostics.
[`docs/errors.md`](docs/errors.md) is the full reference — the class hierarchy, the status
mapping, the 403 reason codes, and what the rate limits actually are:

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

invoice.net_total    # => 1500  (a BigDecimal; #inspect shows 0.15e4)
invoice.vat_total    # => 345
invoice.gross_total  # => 1845   — use .to_s("F") for a plain decimal string

invoice.validate!    # model, bytes, then the bundled XSD — no network
invoice.to_xml       # => "<?xml version=\"1.0\" encoding=\"UTF-8\"?>..."
```

Three things it does for you that the schema requires but you would not think to supply:
the buyer's mandatory `JST` and `GV` flags, the five mandatory `Adnotacje` flags, and one
branch of each mandatory choice wrapper. Omitting any of them is a schema error.

Rounding is explicit, because Polish VAT law permits two approaches and they can differ by
a grosz — pass `rounding: :per_line` (the default) or `:per_summary`.

### Issuing a correction

A `KOR` says what it corrects and by how much. `corrects` names one corrected invoice — call
it again for each of them, up to fifty thousand, which is how a period discount under
art. 106j ust. 3 is issued.

```ruby
correction = Ksef::FA3.build do |f|
  f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: "Prosta 1, 00-001 Warszawa"
  f.buyer  nip: "1111111111", name: "Klient S.A.",     address: "Długa 2, 30-001 Kraków"
  f.number "FK/2026/08/001"
  f.issue_date Date.new(2026, 8, 22)
  f.invoice_type "KOR"

  # `effect` is TypKorekty: when the correction takes effect in the VAT register — 1 at the
  # corrected invoice's date, 2 at this one's, 3 at some other date.
  f.correction reason: "obniżka ceny o 200 zł", effect: 3
  f.corrects number: "FV/2026/02/150", issue_date: "2026-02-15",
             ksef_number: "5265877635-20250826-0100001AF629-AF"

  # The position as it was, then as it now is — two rows sharing one number.
  f.line name: "lodówka", qty: 1, unit: "szt.", net_unit_price: "1626.01",
         net_amount: "1626.01", vat: "23", state_before: true
  f.line name: "lodówka", qty: 1, unit: "szt.", net_unit_price: "1463.41",
         net_amount: "1463.41", vat: "23", row_number: 1

  f.totals gross: "-200.00", net: { "23" => "-162.60" }, vat: { "23" => "-37.40" }
end
```

**The totals are stated, not computed**, and that is deliberate. A correction's summary
buckets are deltas, and FA(3) does not require its rows to determine them — three of the
Ministry's five worked corrections have no usable rows at all, and **two of those carry no
`FaWiersz` whatsoever**. Deriving the figures would invent a tax base the document already
states, so `f.totals` is how a correction says what it does. It takes rate codes, like
`f.line`, and maps them to summary buckets for you.

`f.totals` is **required** once a row is marked `state_before`: such a row shows the position
as it was, so adding it up counts an amount that was already invoiced. `invoice.errors` says
so rather than letting the document out.

Omit `ksef_number` when the invoice being corrected was issued outside KSeF; the document then
carries the `NrKSeFN` marker instead. If the buyer's details are what changed, pass the old
ones as `previous_buyers:` on `f.correction` and give both the old and new record the same
`buyer_id`, which is what links them.

### Collecting an advance, then settling it

A `ZAL` documents money received before the goods are delivered. It has **no invoice rows** —
the order or contract takes their place, per art. 106f ust. 1 pkt 4:

```ruby
Ksef::FA3.build do |f|
  # …seller, buyer, number, issue_date…
  f.invoice_type "ZAL"

  f.order total: "375150"                    # the whole order, including tax
  f.order_line name: "mieszkanie 50m^2", qty: 1, unit: "szt.",
               net_unit_price: "300000", net_amount: "300000",
               vat_amount: "69000", vat: "23"

  f.totals gross: "20000", net: { "23" => "16260.16" }, vat: { "23" => "3739.84" }
end
```

`f.order`'s `total:` is the **whole order including tax** — 375 150 here — while `f.totals`
states the 20 000 actually received. They are different numbers on purpose, and an order
position states its own tax (`vat_amount`) rather than having it computed, because FA(3)
gives it a field of its own.

The `ROZ` issued once the goods are delivered names the advance invoices it settles:

```ruby
f.invoice_type "ROZ"
f.settles ksef_number: "5265877635-20250826-0100001AF629-AF"   # issued through KSeF
f.settles number: "FZ/2026/02/150"                             # issued outside it
```

Its rows describe the goods while `f.totals` states what is **left** to pay, so those two do
not add up to each other — which is why the summary is stated here as well.

### Reading an invoice back

`Ksef::FA3.parse` turns FA(3) XML into the same model the builder produces — useful for an
invoice you fetched from KSeF, or for inspecting one KSeF rejected.

```ruby
invoice = Ksef::FA3.parse(File.read("faktura.xml", encoding: "UTF-8"))
invoice.number        # => "FA/2026/08/001"
invoice.gross_total   # => BigDecimal("1845")
invoice.lines.size    # => 3
```

Two things to know, because they matter more than the happy path.

**Parsing is not validating.** A document KSeF refused still parses — that is the point, since
you usually parse one in order to find out what was wrong with it. Run `invoice.validate!`
yourself if you want the schema checked.

**FA(3) is much larger than this model, so re-serialising a document you did not write loses
whatever it does not cover.** Nothing is thrown away — the whole document stays on
`#raw_document` — but check before you round-trip:

```ruby
invoice.fully_mapped?       # => false
invoice.unmapped_elements   # => ["Faktura/Fa/Platnosc", "Faktura/Podmiot3", ...]
invoice.raw_document        # the complete Nokogiri document, always
```

For an invoice this gem built, the XML always round-trips byte for byte, and
`Ksef::FA3.parse(invoice.to_xml) == invoice` holds whenever the invoice states everything the
document will carry — in practice, set `issued_at` and a `net_amount` per line. Leave them out
and serialisation supplies them (a generation timestamp, and each line's net from quantity ×
price), so the parsed invoice knows two things the original did not.

One field is inherently exempt: **`rounding` is not recorded in an FA(3) document at all**. It
is inferred by asking which strategy reproduces the tax summaries, so a `:per_summary` invoice
whose summaries happen to match `:per_line`'s — the common case — comes back as `:per_line`.

Parsing also refuses what it cannot represent faithfully, rather than guessing: an invoice
type the model does not carry, a row with no `P_12` rate code, a row priced gross, and a buyer
identified by anything other than a NIP. The message says that the document is fine and the
model is the limit, and names the construct.

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
  problem. Idempotent GETs retry with capped exponential backoff, honouring `Retry-After`
  unclamped; every POST surfaces its error to you, so re-sending is always your decision.
- **Thread-safe by requirement.** Configuration is frozen at construction, and a single
  client **is** shareable across threads (Sidekiq is the expected habitat), and that is
  shipped rather than aspirational: the configuration is frozen at construction, the
  connections are stateless, the only mutable state is a memoised credential behind one
  mutex, and no session is ever held on the client — which is why `send_invoice` opens a
  fresh one. A spec drives six concurrent sends and asserts a single authentication.
- **Secrets never logged.** Tokens, JWTs, symmetric keys and IVs are redacted from
  `#inspect` output.

## Roadmap

| Version | Scope |
|---|---|
| 0.1.0 | **Both auth methods** — certificate/XAdES *and* KSeF token — crypto, online sessions, send/status/UPO/download, **three-tier validation** (model *and its byte-level half*, XSD, business), full FA(3) builder for all seven invoice types |
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
