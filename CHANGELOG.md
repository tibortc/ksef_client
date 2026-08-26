# Changelog

All notable changes to this project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Every release entry states the **KSeF API version** and **FA schema revision** it
targets. The Ministry ships changes continuously, so users must be able to answer "which
gem version for which API state".

## [Unreleased]

**Targets:** KSeF API 2.0 · FA(3) `1-0E` · upstream `CIRFMF/ksef-api@1c34fe27`,
`CIRFMF/ksef-client-csharp@406904d6`, `CIRFMF/ksef-pdf-generator@2b7c1dae` (sample corpus,
`docs/REFERENCE.md` §1.4)

> **What "works" means in this section.** As of 2026-08-24 the certificate/XAdES flow **and**
> the full send path have run against the live KSeF TEST service: a session opened, an invoice
> built by this gem encrypted, submitted and accepted, a KSeF number assigned, and the signed
> UPO retrieved and hash-verified. The **KSeF-token auth call and the crypto module went live
> the same day** — a stale `timestampMs` refused by TEST, and `certificateId`/`publicKeyId`
> recomputed against real certificates (run `32704511675`, `docs/REFERENCE.md` §9). What is
> still **WebMock stubs** only: token refresh and invoice download. Batch has no code at all
> yet, so it is absent rather than stubbed.

### Added

- **`docs/field_mapping.md`** — the English↔Polish field table, listing every attribute this
  model carries against the FA(3) element it reads and writes, with the element's XSD type,
  **effective** cardinality and the Ministry's own description in full. **Generated** by `rake fa3:field_mapping`
  from a declared mapping plus the pinned schema, and `rake fa3:verify` fails if the committed
  file is stale — the same gate `lib/ksef/fa3/generated/` gets.

  Three guards make drift loud rather than silent: an element path that does not resolve
  against the schema aborts the run, an attribute that is not a member of its model aborts, and
  a model member that is neither mapped nor given a reason aborts. Adding a field to a model
  without saying where it goes fails the build.

- **Validator tier 3** — `Ksef::FA3::BusinessValidator`, reached through **`Invoice#warnings`**. It holds **one rule**, and the size is the finding rather than a shortfall: no
  file in `CIRFMF/ksef-api` states a reconciliation rule anywhere, and the only business
  validation KSeF ever proposed was withdrawn after it turned out to reject legal invoices. So
  the tier is built on the one grounding that needs no *catalogue*: measurement over the
  Ministry's 26 worked examples. It is **empirical, not definitional** — `P_15`'s annotation says
  nothing about the buckets, and checking `P_13_1` against the rows instead is falsified by ten
  of the fourteen modelled stated-summary samples, because a correction's buckets are deltas.

  **It is advisory and never makes an invoice invalid**, which is the whole design. The rule is
  `Σ P_13_* + Σ P_14_* ≈ P_15` compared over figures the *document* states — never against the
  model's own derivation — with a one-grosz tolerance and a bucket-presence guard. A Polish
  invoice whose nets are computed back from round gross prices misses it by roughly a grosz per
  line and is entirely legal; the Ministry's own Przykład 1 is one. Making that an error would
  refuse legal documents through `Client#send_invoice`, which is exactly what got KSeF's own
  proposed business rule withdrawn. The `W` twins are excluded — `P_14_1W` is a PLN equivalent,
  not a second tax. (`docs/REFERENCE.md` §17.)

- **`Invoice#warnings`**, the advisory tier — empty unless a document's own figures disagree.

- **`Invoice#stated_gross`** and **`Invoice#summary_buckets`**, both public. The first carries
  the document's `P_15` when it differs from the derived figure; the second is the summary as
  the document will carry it, rounded per bucket.

### Fixed

- **A `VAT` invoice derived `P_15` instead of reading it**, so re-serialising the Ministry's
  Przykład 1 produced an invoice a grosz cheaper — 2050.99 against a stated 2051 — with tier 2
  clean, `#errors` empty and `#unmapped_elements` silent, because `P_15` is present either way
  and a path-difference diagnostic cannot see a changed value. Even the round-trip law held: a
  parsed invoice is already a fixed point. The same class as the `P_9A` rounding defect, found
  the same way, by measuring the corpus. `P_15` is now **numerically unchanged** on
  re-serialisation for all 22 modelled samples, and a spec asserts it — numerically, not
  byte-for-byte, since 17 of the 22 reformat (`2051` → `2051.00`). (`docs/REFERENCE.md` §17.2.)

### Added

- **Every markdown file in `CIRFMF/ksef-api` is now pinned** — thirteen more, taking the
  mirror under `docs/upstream/` from 19 of 32 to 32 of 32, all verified byte-for-byte against
  their upstream blob SHAs at the same commit `1c34fe27`. They had been left out deliberately,
  on the rule that only documents a milestone derives facts from belong in the manifest; the
  rule was right and its application was wrong, because two of them define `offlineMode` and
  `hashOfCorrectedInvoice` — parameters `Sessions::Online#send_invoice` has accepted since
  Phase 2. New ledger section `docs/REFERENCE.md` §16.

  The fact that reaches callers: **declaring `offlineMode: false` does not mean KSeF treats
  the invoice as online.** It compares `P_1`'s calendar day against the moment it accepts the
  document, and marks the invoice offline if `P_1` is earlier — an invoice dated yesterday and
  sent one second after midnight is offline (§16.1). Nothing is enforced for this, because it
  is the service's classification and `P_1` is the caller's choice; `#send_invoice` now
  documents it, along with what a *technical correction* actually is (§16.2).

### Fixed

- **`#valid?` answered `true` for XML that is not XML.** `Invoice#errors` ran the schema tier
  over `#to_xml` — bytes this gem had just produced, well-formed by construction — so it could
  not see the input at all, while libxml2's recovery made the parsed tree look fine.
  `Invoice#source_errors` now reports what libxml2 said about the document it was given, and
  `#errors` reports it first. (`docs/REFERENCE.md` §17.5.)

- **Text that is validly encoded but is not UTF-8 crashed the tier meant to report it.**
  `String#valid_encoding?` answers true for `Windows-1250` and `ISO-8859-2` — what a Polish ERP
  emits — so such a name passed every guard and then raised `Encoding::CompatibilityError` out
  of `#errors`, `#to_xml` and `Ksef::Client#send_invoice`. It is now reported, naming the
  encoding. Bytes tagged `ASCII-8BIT` are accepted when they *are* UTF-8, which is what
  `File.binread` produces. (§17.6.)

- **`net_by_rate` and `vat_by_rate` summed a correction's before-state into its after-state.**
  On the Ministry's Przykład 2 that gave 3089.42 against a `net_total` of −162.60 — a per-rate
  VAT report nineteen times the truth, with no error and a passing `#valid?`. Rows marked
  `StanPrzed` are now skipped. (§17.4.)

- **`NaN` and `Infinity` passed the money gate.** `BigDecimal("NaN")` succeeds where
  `BigDecimal("abc")` raises, so a document stating `<P_11>NaN</P_11>` reached the model and
  serialised as `NaN.00` — and broke the `==`/`hash` contract on the way, since `NaN != NaN`.
  Refused now, for the same reason a `Float` is.

- **`Invoice#to_h` handed out the entire source document.** `#inspect` redacts `raw_document`
  so `p invoice` stays readable; `to_h` is a `Data` freebie and did not, so
  `JSON.dump(invoice.to_h)` embedded the whole XML. Both `to_h` and `deconstruct_keys` now
  redact it, as `#==` already ignored it.

- **A parsed invoice could lose the `P_15` it was given.** Settling the rounding strategy by
  copying the invoice meant the copy's constructor re-ran with `stated_gross` already dropped,
  so a `:per_summary` document was re-serialised with a derived total. The strategy is now
  decided from the lines *before* the invoice is built. Every one of the 26 pinned samples
  infers `:per_line`, so the corpus could not have caught it.

- **The advisory tier raised.** `Invoice#warnings` read `P_15` and the buckets off the retained
  document with no tolerance for an empty or unparseable one — the very case
  `Parser#readable_gross` had just been taught to survive. It also stripped namespaces from
  that document in place, mutating the value object's retained source from a read-only query.

- **A unit price was silently rounded from eight decimal places to two.** `P_9A` — and `P_9AZ`
  on an order position — is `TKwotowy2`, *"22 znaki max, w tym 8 znaków po przecinku"*, not the
  two-place `TKwotowy` of the amounts it produces. A row priced at `1626.0125` is schema-valid;
  this model read it, stored `1626.01` and re-emitted `1626.01`, with `#errors` empty and
  `#unmapped_elements` empty because the element path never changed. A **stated amount altered
  in silence**, which is the most serious defect this model can carry. `Formatting.unit_price`
  keeps up to eight places and still pads `150` to `150.00`, and `TKwotowy2`'s pattern allows
  one to eight, so every existing document is byte-identical under the fix.
  (`docs/REFERENCE.md` §8.6.)

- **`Correction#exchange_rate_before` held a rate the document cannot carry.** `KursWalutyZK`
  is `TIlosci`, whose six decimal places are a ceiling and not a preference. Stored unrounded,
  a correction built with `4.12345678` emitted `4.123457` and then failed the round-trip law
  against itself — with tier 2 silent, because what reached the document was valid. It was the
  only field in the model not rounded to its element's scale (§8.2b).

- **`Line#vat` answered `0` for a row whose tax is unknown.** `#net` and `#gross` already
  answered `nil` for a row that states no amount; `#vat` claimed the tax was nothing, so
  `lines.sum(&:vat)` under-reported in silence while `sum(&:net)` raised. It now answers `nil`
  for that row and keeps `0` for the case that really is zero — a rate code such as `zw`, `oo`
  or `np I`, where the amount is stated and carries no tax.

- **Tier 1 addresses a rateless row to the field that fixes it**, `lines[0].vat_rate` rather
  than `lines[0]`. Supplying `P_12` is the whole remedy, so the issue points at it. A row that
  states no amount stays addressed to the row, because its remedies are several.

- **VAT rate code `np II` reported into the wrong summary bucket** — the third bug of this
  exact class, after the shared-bucket accumulation bug and rate code `3`. `np II` is
  *"świadczenie usług o których mowa w art. 100 ust. 1 pkt 4 ustawy"*, and `P_13_9` is *"suma
  wartości świadczenia usług, o których mowa w art. 100 ust. 1 pkt 4 ustawy"* — the same
  statutory scope, word for word. `P_13_8`, where both `np` codes went, reads *"z wyłączeniem
  kwot wykazanych w polach P_13_5 i **P_13_9**"*: the one bucket `np II` may not use. The
  effect was an intra-EU services figure declared in the wrong category on an XSD-valid
  document that tier 1 passed. `VatRate.unreachable_elements` now also names `P_13_11` (the
  margin scheme, declared through `Adnotacje/PMarzy` rather than a rate), and a spec asserts
  every *other* net bucket is reachable — an incomplete list there is what made `P_13_9` look
  like a deliberate gap (`docs/REFERENCE.md` §8.1a).

- **Two more falsifications of the tier 1a contract** ("what this passes, `#to_xml` can
  serialise"):
  - A Hash nested under a **leaf** annotation — `annotations: {"P_16" => {"X" => 1}}` — passed
    the model tier and then made `#to_xml` raise. The recursion added in the previous release
    resolved each child's type the way the serializer does, but read a leaf's empty element
    list as "the codegen changed" rather than "this element takes text".
  - `address_errors` still checked `respond_to?(:line1)` and then read `line2` and `country`,
    so an object answering only the first made `#errors` raise `NoMethodError` — the symptom
    the surrounding guards had already been changed to `is_a?` to prevent.

- **A correction built without stated totals derived its summary from the rows, counting
  `StanPrzed` rows as sales.** `docs/REFERENCE.md` §8.4 says a correction's summaries are read
  and never computed; that held in the parser and not in the serializer, which fell back to
  the line-derived buckets whenever no `Totals` was given. A `StanPrzed` row is the position
  *as it was before the correction* — already invoiced on the original document — so summing
  it counts the amount twice with the wrong sign. The Ministry's Przykład 2, built through
  this gem's own DSL without `f.totals`, declared `P_15 = 3799.98` for a correction worth
  `-200.00`: a refund emitted as a charge, XSD-valid, with `invoice.errors` empty and
  `#unmapped_elements` showing nothing. **Tier 1 now requires stated totals whenever a line is
  marked `state_before`** — scoped to the marker rather than to the invoice type, because a
  correction whose rows already *are* the deltas computes correctly, and Przykład 3 is exactly
  that shape.

- **`NrWierszaFa` was read as octal.** `Formatting.integer` called `Integer(value)` with no
  base, so Ruby honoured a leading zero. `<NrWierszaFa>010</NrWierszaFa>` is schema-valid and
  means ten; it parsed as **eight** and re-serialised as `8` — in the one field that pairs a
  correction's before/after rows once `UU_ID` is dropped. `"08"` failed the other way, raising
  on a document the schema accepts. A `Float` is now refused rather than truncated.

- **Tier 1 rejected KSeF numbers the FA(3) schema allows.** It judged a referenced
  `NrKSeFFaKorygowanej` with `Ksef::KsefNumber::FORMAT`, which comes from the **OpenAPI
  contract** and admits only the NIP issuer form; the **XSD** additionally admits `M\d{9}` and
  `[A-Z]{3}\d{7}`. The two artifacts are both right about their own domain — the contract
  governs lookup URLs, the XSD governs documents — so tier 1 no longer checks the format and
  tier 2 owns it (`docs/REFERENCE.md` §8.4b).

- **Silent drops and silent rewrites**, each found by the same audit:
  - A **symbol-keyed** element passed the serializer's own unknown-key check, which compares
    `keys.map(&:to_s)`, and was then dropped by a write loop asking `key?(name)` for a String.
  - An **absent `Adnotacje`** was read as the defaults, emitting eight affirmative tax
    declarations the document never made. It now reads as "nothing declared".
  - A **`DaneFaKorygowanej` stating neither branch** of the schema's choice was re-serialised
    with `NrKSeFN`, asserting the corrected invoice had been issued outside KSeF. Refused.
  - `Ksef::FA3::Totals` **dropped a bucket** given under two spellings (`:P_13_1` and
    `"P_13_1"`); it now refuses the collision.
  - The `Adnotacje` key check reached one level deep while the serializer recurses, so a bad
    nested key passed the model and raised on the way out.

- **Round-trip equality** held for fewer invoices than documented. `Ksef::FA3.parse(x.to_xml)
  == x` now survives `number: 123`, `vat: 23`, a buyer flag given as `"1"`, and a
  `row_number` that merely repeats its position — all of which describe exactly the document
  their canonical spellings do. Text bound for an `xsd:token` element is canonicalised on the
  way in, which also closed a case where `vat_rate: " 23 "` passed tier 1 and then made
  `#to_xml` raise.

- **Errors that escaped this gem's hierarchy.** `Invoice#errors` is documented to answer
  rather than raise; it raised for a mojibake NIP, for a mojibake KSeF number, and for a
  `totals:` or `correction:` of the wrong class (the duck-typed guards accepted this gem's
  *other* value objects, then called methods they do not have). `Formatting.date_time` raised
  `NoMethodError` for a non-time, `Builder#totals` for `net: nil`, and `Correction.new` mangled
  a Hash into pairs. All now `Ksef::ValidationError` — except the Hash, which no longer
  becomes pairs at all: it is carried as a single entry and reported by `#errors` as
  `correction.corrected[0]: is not a Ksef::FA3::CorrectedInvoice`, the addressed error the
  rest of this bullet is about.

- **`Formatting.to_date` guessed.** `Date.parse("junk")` answers the first of June, and
  `"12"` answers the twelfth of the current month — a value that changes with the clock.
  A String must now be ISO-8601, which is the only form an FA(3) document can carry.

- **`BigDecimal("-0.00")` broke the `==`/`hash` contract**, comparing equal to `0.00` while
  hashing differently, so a line whose net arrived as `"-0.00"` failed as a Hash key. Negative
  zero is normalised.

- **Frozen state.** `Ksef::FA3::Correction` no longer freezes the caller's own array, and
  `Totals#buckets` and `Invoice#lines` are frozen, so an invariant cannot be edited around
  after construction.

### Added

- **`UPR`, `KOR_ZAL` and `KOR_ROZ` — the last three types. All seven now build, parse,
  round-trip and validate** (DESIGN.md §7.4, `docs/REFERENCE.md` §8.6). Twenty-two of the
  Ministry's twenty-six worked examples go through end to end; the four that do not are
  refused for a **construct** rather than for their type — two priced gross, two identifying
  their buyer by something other than a NIP.

  `KOR_ZAL` and `KOR_ROZ` needed one element between them. **`P_15ZK` means two different
  things**, and the invoice type decides which: the amount *paid* before the correction on a
  `KOR_ZAL`, the amount *left to pay* before it on a `KOR_ROZ`. `Correction#paid_before`
  carries the figure and does not name it more precisely than the schema does.

  `UPR` needed the real change: **a row that states no amount at all.**

  ```ruby
  f.invoice_type "UPR"
  f.line name: "wiertarka Wiertex mk5"        # and nothing else — this is the whole row
  f.totals gross: "450", net: { "23" => "365.85" }, vat: { "23" => "84.15" }
  ```

  Every child of `FaWiersz` but `NrWierszaFa` is `minOccurs="0"`, so an amount-less row is
  the schema's own default and this model was the strict one. `Ksef::FA3::Line#net` now
  answers **nil rather than raising**, and nil is not zero: the row states nothing, rather
  than stating that it is worth nothing. The same change unblocked **Przykład 7**, the one
  Ministry correction this model could not read — its single row names goods, a `CN` code and
  a quantity, with no amount anywhere — so all five corrections now go through.

  **The parser stopped refusing two shapes, and tier 1 took them over.** An unpriced row, and
  a row with an amount but no `P_12`, are both legal. But on an invoice that *derives* its
  summary from its rows the amount is simply absent from the tax base, and neither tier can
  see that — the XSD is blind to arithmetic and `#unmapped_elements` to values. So the check
  is line-addressed and fires only where the summary is derived:

  ```
  lines[0]: states no amount, and this invoice derives its summary from its rows…
  lines[1]: states an amount but no P_12 rate code, so there is no bucket to put it in…
  ```

  **Gross pricing is still refused at parse time**, and the distinction is deliberate: a
  gross-priced row carries a number this model has nowhere to put, so reading it would drop a
  real amount. An unpriced row has no number to drop.

- **`ZAL` and `ROZ` — the advance invoice and the settlement invoice that closes it out**
  (DESIGN.md §7.4, `docs/REFERENCE.md` §8.5). Four of the seven types now build, parse,
  round-trip and validate, and fifteen of the Ministry's twenty-six worked examples go through
  end to end.

  A `ZAL` documents money received before delivery, and carries **no invoice rows at all** —
  the order or contract of art. 106f ust. 1 pkt 4 takes their place:

  ```ruby
  f.invoice_type "ZAL"
  f.order total: "375150"                    # the whole order, including tax
  f.order_line name: "mieszkanie 50m^2", qty: 1, unit: "szt.",
               net_unit_price: "300000", net_amount: "300000",
               vat_amount: "69000", vat: "23"
  f.totals gross: "20000", net: { "23" => "16260.16" }, vat: { "23" => "3739.84" }
  ```

  `f.order`'s `total:` is `WartoscZamowienia`, the whole order **including tax** — 375 150
  against 20 000 actually received. They are different numbers, and conflating them would be a
  large error. An order position states its own tax through `vat_amount:`, because FA(3) gives
  it a field (`P_11VatZ`) that an invoice row does not have; nothing about an order is derived.

  The `ROZ` issued once the goods are delivered names each advance invoice it settles, in
  either of the two forms the schema allows:

  ```ruby
  f.settles ksef_number: "5265877635-20250826-0100001AF629-AF"   # issued through KSeF
  f.settles number: "FZ/2026/02/150"                             # issued outside it
  ```

  **The choice here is inverted from a correction's**: `NrKSeFZN` marks an advance invoice
  issued *outside* KSeF and pairs with the plain number, while the KSeF branch is the number
  alone. The two branches name different fields, so `Ksef::FA3::AdvanceInvoice` carries both
  and requires exactly one — a single nil-able field, which was enough for `CorrectedInvoice`,
  would assert the wrong provenance here.

  **Both types state their tax summary rather than deriving it**, and that is measured rather
  than assumed: across every sample of the family the stated buckets never equal the row
  totals. A `ZAL` has no rows to derive from; a `ROZ` describes the goods in its rows and
  states what is left to pay **after** the advance — an amount this document does not contain
  enough to compute. Tier 1 now requires a stated summary on three structural triggers: a
  `state_before` row, an order, or a settled advance invoice.

  Not modelled, and visible through `#unmapped_elements` if a parsed document carries them:
  `ZaliczkaCzesciowa` (in none of the twenty-six samples), `P_15ZK` (scoped to the `KOR_`
  combinations, which are the remaining work), `Platnosc` and `DodatkowyOpis`.

- **`KOR`, the correction — building, parsing and validating** (DESIGN.md §7.4,
  `docs/REFERENCE.md` §8.4). A correction says what it corrects, why, and when it takes effect:

  ```ruby
  f.invoice_type "KOR"
  f.correction reason: "obniżka ceny o 200 zł", effect: 3
  f.corrects number: "FV/2026/02/150", issue_date: "2026-02-15", ksef_number: "…"
  f.totals gross: "-200.00", net: { "23" => "-162.60" }, vat: { "23" => "-37.40" }
  ```

  `corrects` may be called up to fifty thousand times — art. 106j ust. 3 lets one correction
  carry a discount across a whole period — and takes no `ksef_number` when the corrected invoice
  was issued outside KSeF, which writes the `NrKSeFN` marker instead. `Ksef::FA3::Correction`
  also carries `period`, `corrected_number`, and the previous state of either party
  (`Podmiot1K`/`Podmiot2K`), linked to the live record by the `buyer_id` the schema calls
  `IDNabywcy`. A row can be marked `state_before: true` to show a position as it was, and
  `row_number:` gives the before/after pair the shared number that ties them together.

  **A correction's tax summary is stated, not computed**, through `f.totals` — and that is the
  decision worth knowing about. Its buckets are *deltas*, and FA(3) does not require the rows to
  determine them: of the Ministry's five worked corrections, two carry no `FaWiersz` at all and
  a third has a row stating no amount anywhere. Deriving the figures would invent a tax base the
  document already states. `Invoice#lines` may therefore be empty, but **only** when totals are
  stated; without either there is nothing to declare tax from, and the constructor says so.

  Four of the Ministry's five corrections now parse, re-serialise and validate; the fifth is
  refused for a row that states no price at all, with a message naming the construct.
  `Ksef::FA3::Totals` is keyed by summary-element name rather than rate code, because that
  mapping is not invertible — `"23"` and `"22"` share `P_13_1`.

  One thing validation deliberately does **not** do: check the CRC-8 of a referenced KSeF
  number. All six such numbers in the Ministry's own worked corrections fail it — they are
  well-formed placeholders — so the check would refuse the Ministry's own documents. The shape
  is checked; the checksum is not (`docs/REFERENCE.md` §8.4a).

- **`Ksef::FA3.parse` — reading an FA(3) document back into the model** (DESIGN.md §7.6).
  The round-trip law runs green over a pinned corpus of the Ministry's own sample invoices,
  which turned out not to live in `ksef-api` at all: they come from `CIRFMF/ksef-pdf-generator`
  and `CIRFMF/ksef-client-csharp`, each pinned at its own commit (`docs/REFERENCE.md` §1.4).

  Three things are worth knowing before using it. **Parsing is not validating** — a document
  KSeF rejected still parses, because inspecting one is usually *why* you are parsing.
  **`#raw_document` is always retained**, and `#unmapped_elements` names what re-serialising
  would drop, computed by difference against the serializer so it cannot drift from what is
  actually written; FA(3) is much larger than this model, so re-serialising a document you did
  not write is lossy. And it **refuses what it cannot represent faithfully** rather than
  guessing: an invoice type the model does not carry, a row with no `P_12` rate code, a row
  priced gross, a row that states no price at all, and a buyer identified by anything but a
  NIP. Those messages say the document is
  fine and the model is the limit, and name the construct.

- **Validator tier 1, in two halves** (DESIGN.md §7.7, amended). `Ksef::FA3::ModelValidator`
  checks the invoice object — required fields, enum membership read from the generated schema
  metadata, NIP checksums, string lengths against the schema's own facets, and an issue date
  that is not in the future. `Ksef::FA3::DocumentValidator` checks the serialized bytes for the
  four admission rules of `docs/REFERENCE.md` §15.1 that **neither a model tier nor tier 2 can
  see** — a byte-order mark, a prolog declaring anything but UTF-8, processing instructions, and
  the Unicode characters KSeF refuses — plus that the bytes are UTF-8 at all, and the
  million-byte ceiling, which `max_bytes:` overrides because upstream marks it a negotiable
  default rather than a limit of the format.

  `Invoice#errors` runs model → document → schema and returns `Issue` values carrying a field
  path (`lines[2].vat_rate`), so a caller learns which value to fix rather than reading a
  libxml2 message about a facet. `#validate!` lists every problem instead of the first.

  The model tier short-circuits deliberately: serialisation *raises* on a bad NIP, a nameless
  seller or a line with no derivable net, so running it after a model failure would collapse a
  list of addressed errors into a single exception. Its aim is the stronger statement — *what
  the model tier passes, `#to_xml` can serialise* — held as an aim rather than a proof, since a
  review falsified it twice before release. And `#errors` reports rather than raises, including
  for text tagged UTF-8 that is not: a method asked what is wrong should answer.

- **`Ksef::FA3::Invoice#annotations`** — the `Adnotacje` block is carried, not defaulted, so
  re-serialising cannot deny a declaration the document made (cash accounting, reverse charge,
  split payment, a real VAT exemption).

- **Pinned the Ministry's 26 worked FA(3) examples** as test fixtures
  (`spec/fixtures/fa3/mf-samples/`, `docs/REFERENCE.md` §1.5) — all seven `RodzajFaktury` values,
  and the only corpus of non-`VAT` invoice types in existence: two independent sweeps of every
  CIRFMF repository, all branches and full history, found every FA(3) fixture there to be `VAT`.
  All 26 validate against the pinned XSD. They are not packaged in the gem.

  This is the first artifact pinned from outside the CIRFMF organisation, so §1.2's MIT reasoning
  does not reach it; the redistribution rests on `podatki.gov.pl`'s site-wide statement that use
  requires no consent, with the caveat — recorded rather than glossed — that the files sit on a
  subdomain carrying no licence statement of its own.

- **Pinned `faktury/weryfikacja-faktury.md`** (`docs/REFERENCE.md` §15), the invoice-admission
  rules KSeF applies on submission. It settles two open questions: validator tier 3's
  business-rule catalogue is **absent from upstream**, not merely unpinned (§15.6), while
  tier 1 — which had no first-tier source at all — is now specified exactly. NIP checksums are
  validated **in production only** (§15.3), so no TEST run can ever exercise that rule.

- **`Ksef::Client` — the facade, and DESIGN.md §8's snippet now runs.** A spec drives that
  snippet as written, from `Ksef::FA3.build` through `send_invoice`, `wait_until_accepted`
  and `upo`, so the README's headline example can no longer drift from the code.

  **`Receipt#reference` returns `self`,** and that is not a trick. §8 reads
  `client.wait_until_accepted(result.reference)`, which looks like it wants a string — but
  every status and UPO endpoint is keyed on **both** the session and the invoice, so an
  invoice reference alone looks nothing up. Rather than bend §8 into two arguments, or cache
  the session on a client that has to stay thread-safe, the pair *is* the reference.

  **`#upo` uses the metered per-invoice route**, against §14.2's stated preference —
  deliberately, and only there. Obtaining the unmetered pre-signed link costs a metered
  status call first, so for one invoice the direct route is one request rather than two. The
  link earns its keep on collective UPOs, which is what `#collective_upo` uses it for.

  Thread-safe by construction rather than by promise (DESIGN.md §5.2): frozen configuration,
  stateless connections, and the only mutable state — the memoised credential — behind one
  mutex. **No session is ever held on the client**, which was the deciding argument for
  opening a fresh one per send: a cached session would be mutable state two threads could
  submit into at once. A spec runs six concurrent sends and asserts one authentication.

  Authentication is lazy: constructing a client performs no I/O, and the first call needing
  a credential runs the whole KSeF-token flow.
- **`Ksef::Invoices::Client`** — `GET /invoices/ksef/{ksefNumber}`, returning the invoice
  verbatim. 8 req/s but only **64 req/h**, one of the tightest ceilings in the API: it is a
  per-document fetch, so a month of invoices exhausts the hourly allowance long before the
  per-second limit bites, and the 0.2 package export is the bulk route. The number is
  CRC-checked locally rather than spending one of those 64 requests on a 404.
- **`Ksef::UPO` — retrieval, over a connection that has no credential.** A UPO is the legal
  proof that KSeF received an invoice, fetched over an unauthenticated storage link, and
  three properties follow from that.

  **The access token is never sent to a `downloadUrl`.** Those links are pre-signed Azure
  Blob URIs carrying their own authorisation in the query string, and the contract says
  outright not to send the token — it would hand a live KSeF credential to third-party
  storage. Rather than remembering that per call site, `Ksef::HTTP::Connection.storage`
  builds a second connection with **no bearer and no base URL**, so no code path can leak
  one. It also omits JSON encoding and parsing, since a UPO is XML that must survive as the
  exact bytes received.

  **The bytes are archived verbatim.** The Ministry's XAdES signature covers octets, not an
  abstract tree, so even a lossless XML round-trip can produce a document that no longer
  verifies. `UPO::Document` holds the received string and offers no parsed form, no
  `#to_xml` and no re-encode; `#write` uses `binwrite` so a newline translation cannot
  corrupt an archive.

  **`x-ms-meta-hash` is verified** — the only integrity check available on bytes fetched
  outside the API. `#fetch` prefers the unmetered, hash-verified link and falls back to the
  metered route when it expires, which is §14.2's resolution after an earlier reading had it
  backwards. `for_ksef_number` parses the number first, so a mistyped one fails on its CRC-8
  locally rather than as an opaque 404.
- **`Ksef::UPO::Validator`** — offline schema validation for a received UPO, and the place
  §14.3's trap would otherwise have caught us. `upo-v4-3.xsd` fixes the receiving party's
  name to `"Ministerstwo Finansów"` while every non-production environment appends a marker,
  so **a strict validator rejects every UPO that TEST and DEMO issue** — measured: all six of
  upstream's own worked examples fail upstream's own schema, each with exactly one error,
  always that element.

  The mismatch is reported as a **warning** rather than relaxing the constraint, which keeps
  strictly more: in production the fixed value is presumably right, so a mismatch there is a
  real anomaly a relaxed schema would never mention. The observed value is read from the
  document by XPath, and doubles as a way to tell which environment issued a UPO.

  **There is deliberately no `validate!`.** A UPO is legal proof that an invoice was
  received; whether it satisfies a schema is never a reason to discard the bytes or fail an
  operation that already succeeded at the far end. Offering a raising method would make
  gating the path of least resistance, so a spec asserts its absence.
- **`Ksef::IntegrityError`** — raised when downloaded bytes do not match the published hash.
  Its own class because the right response is unlike every other error here: *fetch it
  again*. Nothing is wrong with the request, the credentials or the document — the transfer
  was corrupted. Silently archiving corrupt bytes as proof of receipt is the one outcome
  worth refusing loudly.
- **`Ksef::Sessions::Status`** — single-shot session and per-invoice reads, plus
  deadline-bounded waits. Capped exponential backoff (1s, 2s, 4s … 30s, five-minute
  deadline) rather than the reference clients' fixed 1s × 60: at 1/s a single wait spends 60
  of the 1200 requests an hour a context gets, and a 60-second ceiling is far too short for
  a large session. A timeout says the operation has **not failed but outlasted the wait**,
  because conflating the two invites a needless resend.

  **It exposes no list-sessions call at all.** `GET /sessions` is 10 req/min — the tightest
  budget in the API — against 1200/h for the two endpoints polling should use. Omitting the
  method is the simplest way to make that mistake impossible rather than merely discouraged.

  `InvoiceState` surfaces what the endpoint already returns instead of making callers fetch
  it twice: the per-invoice UPO link, and on a duplicate the **original** submission's KSeF
  number and session reference, which is what makes a resend reconcilable. `UpoPage` keeps
  its pre-signed URL out of `#inspect` and `#to_s` — the link carries its own authorisation
  in the query string, so it is a credential — while still exposing it to a caller that asks.
- **Corrected: both `100` and `150` mean "keep polling"**, not `150` alone. The earlier
  reading came from `OnlineSessionUtils.cs`, whose poller returns as soon as the code is
  anything but `150`, and it is wrong on the contract's own wording — `100` is *"przyjęta do
  dalszego przetwarzania"*, accepted for **further** processing, so an invoice sitting there
  is undecided and has no KSeF number. A poller that stops at `100` reports a pending
  invoice as though it were settled.

  The rule is now `code < 200 is in progress` rather than a list of intermediate codes, so a
  code upstream adds later behaves correctly by default. This is deliberately the inverse of
  the treat-the-unknown-as-terminal rule used for *authentication* status, and the asymmetry
  is justified in both places: auth polls without a deadline so it must not loop for ever,
  while session polling is bounded — and "unresolved" is a more honest answer about an
  invoice than "prematurely final". The same rule makes `170` → `200` work for sessions,
  where closing starts asynchronous UPO generation and "closed" is one step short of done.
- **`Ksef::Sessions::Online` — open, send, close.** Stateless and thin, like
  `Auth::Client`: it maps requests and responses and holds no session of its own. Both
  official clients do the same, threading the reference through as a parameter.

  **The `Encryptor` is bound to the `Session`, not passed per send**, and that is the
  decision worth knowing about. The symmetric key is agreed once, at open, and every invoice
  in the session is encrypted under it — so an invoice encrypted with any other key is
  undecryptable at the far end, and the only symptom is per-invoice status `435` arriving
  **asynchronously**, long after the send returned `202`. There is no synchronous error to
  catch. Binding the key to the session makes the mistake unrepresentable rather than merely
  documented, the same move as `Encryptor#seal` returning both digests together.

  Sends `X-KSeF-Feature: upo-v4-3` on open — a header in neither the contract nor any
  upstream prose, but sent by both official clients, which selects the UPO format the session
  produces. This gem bundles `upo-v4-3.xsd` and nothing else, so silence would mean accepting
  a version it might not be able to validate (`docs/REFERENCE.md` §14.6).

  `formCode` comes from the contract rather than from `srodowiska.md`, whose prose misspells
  the PEF system codes and omits `FA_RR (1)` entirely. Reference numbers are shape-checked
  before reaching a URL path.
- **`send_invoice` opens a fresh session per call**, with `client.session { |s| ... }` for
  deliberate batching. Resolves the session-reuse `[VERIFY]` in DESIGN.md §6.5, which the
  facts left open: sessions last 12 hours and take 10 000 invoices, and neither official
  client offers a composite to copy. A reused session is mutable state on a client that must
  be thread-safe; an opened-but-unused session is cancelled with status `440`; and the API
  returning the *original's* KSeF number on a duplicate suggests resends are an expected
  hazard rather than one to make likelier by hiding session state.
- **`Ksef::KsefNumber`** — parses and validates the identifier KSeF assigns to
  an accepted invoice. CRC-8 with polynomial `0x07`, verified against the Ministry's own
  documented example, which doubles as the golden vector. Checking the checksum locally is
  the point: these numbers get copied between systems and read down telephones, and a CRC-8
  catches exactly those slips, turning a silent lookup failure into a specific error naming
  both the carried and the computed value. `assigned_on` is a `Date` because it is not
  metadata — it is the invoice's **official receipt date**.
- **`Ksef::Auth::AccessToken`** — tracks expiry from the response's `validUntil`, never by
  decoding the JWT: §4.3 excludes the `jwt` dependency and the contract carries `validUntil`
  precisely so no decoding is needed. Refreshes at ~80% of the observed lifetime rather than
  on expiry, so a request never carries a credential that dies mid-flight — on an invoice
  submission, a failure that *might* have been delivered is the situation this gem works
  hardest to avoid. Thread-safe with the staleness check re-run inside the lock, so a burst
  of threads yields one refresh rather than a stampede.
- **`Ksef::Crypto` — the encryption layer.** AES-256-CBC with PKCS#7 for payloads,
  RSA-OAEP with SHA-256 *and* MGF1-SHA-256 for wrapping, and the Ministry's published
  certificates fetched, cached and selected by declared usage. Every parameter is ledgered
  at `docs/REFERENCE.md` §10 from first-tier documentation, not inferred from client
  behaviour.

  **The IV is not prefixed to the ciphertext**, whatever `sesja-interaktywna.md` says. It
  travels once as a discrete field of the session-open request, and each invoice ciphertext
  is bare. There is now a fourth witness against the prose, and it is the sharpest:
  upstream's own worked example pairs a 6480-byte invoice with a 6496-byte ciphertext, which
  is exactly one block of PKCS#7 padding and no room at all for a 16-byte IV (§14.1).

  DESIGN.md §6.4 asked for golden vectors ported from the C# client. **There are none to
  port** — neither reference client commits plaintext/ciphertext pairs. The primitives are
  pinned to their standards instead: **NIST SP 800-38A F.2.5** for AES-256-CBC, byte for
  byte, and **FIPS 180-4** for SHA-256. The two parameters that genuinely could have gone
  wrong are pinned behaviourally: the longest accepted OAEP plaintext is 190 bytes, which
  fixes the digest at SHA-256 without trusting an option name, and a ciphertext made with
  MGF1-SHA-256 provably fails to decrypt under MGF1-SHA-1. That last one matters —
  OpenSSL's MGF1 digest defaults to SHA-1, so naming only `rsa_oaep_md` yields a different
  scheme that fails at the far end and nowhere else.
- **`Ksef::Crypto::PublicKeys`** — `GET /security/public-key-certificates`, cached for an
  hour behind a mutex, with the documented selection rule: filter by usage, require validity
  *at the moment of use*, and prefer the latest `validFrom` where several qualify. The
  endpoint is unauthenticated, so keys can be fetched before any credential exists.

  Two rotation modes must not be conflated. Re-certification keeps the key pair, so
  `publicKeyId` is unchanged; key rotation changes it, and an **emergency** rotation drops
  the old certificate from the list immediately. `#with_key_rotation` implements §10.2's
  recovery for that window — on a `400`/`21470` it re-fetches and re-runs the operation.
  That is remediation and not a blind replay: a 21470 means the request was declined
  outright, and the second attempt carries a *different* key identifier, so DESIGN.md
  §6.7's never-auto-retry-a-POST rule is intact. Any other API error surfaces untouched.
- **`Ksef::Crypto::Encryptor#seal`** returns the ciphertext together with the hash *and*
  size of both the plaintext and the ciphertext. `POST /sessions/online/{ref}/invoices`
  requires all four (§11.1) and hashing the wrong artifact is a silent error only the server
  can catch, so the two digests are produced together rather than left to a caller to pair
  up. Sizes are byte counts, not character counts — the distinction is not academic when
  every KSeF document is full of Polish characters.
- **`Ksef::Auth::Token` — the KSeF-token credential of DESIGN.md §8**, and
  `Auth::Client#submit_ksef_token`. **Both authentication methods now exist.** The token is
  never sent as a bearer: it is RSA-OAEP-encrypted alongside the challenge's own
  `timestampMs`, which the docs describe as a replay nonce — so the method takes a
  `Challenge` object rather than its string, and refuses the string outright. Inventing the
  timestamp locally would fail with nothing to point at.

  Only `Nip` and `InternalId` contexts are offered, though the contract's enum has four: a
  token can only be *issued* in those two, so a token for the other two cannot exist to be
  presented (§4.1). `#to_s` and `#inspect` are redacted; the token is reachable only by
  building the request.
- **`Ksef::CryptoError`** — a new branch of the DESIGN.md §6.7 hierarchy, for "no published
  key is valid for this usage" and for malformed key material. Neither an `ApiError` (the
  request succeeded; the list has nothing usable) nor a `ConfigurationError` (documented as
  local and pre-request). Reasoning recorded at `docs/REFERENCE.md` §10.3, alongside the
  other decisions upstream does not state.
- **Live integration for the crypto module** (`spec/integration/crypto_spec.rb`). Two things
  no offline test can reach: that `certificateId` and `publicKeyId` are derived as §10.2
  claims — recomputed from the real certificates, which matters because the library only
  ever echoes the server's value back — and that KSeF **decrypts** what this gem wrapped,
  since an access token is issued only if the RSA-OAEP ciphertext unwrapped to the right
  `token|timestampMs`. Unlike the XAdES suite this needs no PESEL, so it reuses the stored
  `KSEF_TEST_NIP`/`KSEF_TEST_TOKEN` rather than provisioning a test person.

  **Superseded 2026-08-24 — the nightly ran and all three specs went green.** `crypto_spec`
  resolved both of its open questions against live TEST (run `32704511675`,
  `docs/REFERENCE.md` §9), so the crypto module and the KSeF-token auth call *are*
  live-verified. As written at the time: *"These specs have only ever run against stubs. They
  are written, not yet exercised; the nightly is their first real run. Nothing in the crypto
  module is live-verified."*
- `rake fa3:generate` — codegen producing committed `lib/ksef/fa3/generated/`: 59 content
  models and 21 enumerations read from the pinned FA(3) XSD. Hand-written models consume
  this for element ordering, occurrence rules and enum membership.
- `rake fa3:verify` — regenerates and fails on any byte difference, so a non-deterministic
  generator or a stale `generated/` breaks the build. Runs in the default task and on every
  CI matrix leg.
- Pinned `AuthTokenRequest` schemas (auth v2-0 and v2-1) ahead of the certificate auth flow.
- **FA(3) models and serializer.** A plain `VAT` invoice can be described with English
  keyword arguments and serialised to schema-valid XML. `Ksef::FA3::Invoice`,
  `Subject`, `Line`, `Address`, plus `NIP` checksum validation, `VatRate` bucket mapping and
  centralised `Formatting`. Both rounding strategies from DESIGN.md §7.3 are implemented.
- **`Ksef::FA3::Validator`** — offline XSD validation against the bundled schema. The
  schema's one remote `xsd:import` is redirected in memory, so validation needs no network
  and the pinned file stays byte-identical.
- The serializer reads element order from the generated metadata rather than hand-listing
  it, and raises on element names the schema does not define at that position instead of
  dropping them silently.
- **Live integration specs, and the nightly schedule enabled.**
  `spec/integration/auth_flow_spec.rb` exercises the real authentication flow against TEST.
  Opt-in twice over — tagged `:integration` *and* excluded unless `KSEF_INTEGRATION=1`,
  because RSpec ANDs exclusion filters with CLI inclusions, so a tag alone would either
  always run or never run. WebMock is re-enabled around each example rather than globally,
  so a failure cannot leave the network open for whatever runs next.

  **DESIGN.md §12 item 4 is resolved.** Running the bootstrap against TEST established what no
  offline test could: KSeF accepts the XAdES-BES signature this gem produces, the 2.0
  namespace is correct, `/testdata/person` really is unauthenticated, and a self-signed
  certificate is accepted on TEST. Recorded at `docs/REFERENCE.md` §6a.4.
- **`rake auth:bootstrap`** — provisions a TEST credential end to end, retiring the
  workaround `docs/REFERENCE.md` §6a.2 used to describe (a one-time out-of-band mint via
  the official C# client). It invents a checksum-valid NIP and PESEL, registers them
  through the **unauthenticated** `/testdata/person` endpoint — the only reason the chain
  is not circular, since `POST /tokens` needs a session — authenticates by XAdES with a
  self-signed certificate, and mints the token. A real qualified certificate can be
  supplied instead.

  It lives in `tasks/`, so it is never packaged, but it is **not** an untested script:
  every method is covered against stubs. A checksum bug would otherwise surface as an
  opaque rejection from a remote server. It refuses any environment whose `test_data_api?`
  capability is false, so DEMO is refused as well as PROD, and the guard is on the
  capability rather than the name so a `custom` environment cannot slip past.
- **`Ksef::Auth::Client`** — the six HTTP calls of the authentication flow, with typed
  responses (`Challenge`, `Initiation`, `OperationStatus`, `Tokens`, `TokenInfo`) and a
  poller. Deliberately thin: it maps requests and responses and nothing else. Only
  `wait_until_complete` has policy, and it has **no timeout by default** — on DEMO and PROD
  the operation legitimately stays "in progress" while the certificate's status is checked
  with its issuer over OCSP/CRL, so a fixed deadline would report failure for
  authentications that were about to succeed.
- **`Ksef::Auth::Status`** — the twelve authentication status codes. These are not HTTP
  statuses; they arrive inside a 200 response. An unrecognised code is treated as
  **terminal**, because assuming otherwise polls a dead operation for ever, and elapsed
  time cannot distinguish "still legitimately 100" from "stuck".
- `TokenInfo` redacts **both `#inspect` and `#to_s`**. Redacting only `#inspect` leaves the
  leak that actually happens — interpolating a token into a log line. Extracting the value
  is an explicit `#token` call, and `Auth::Client` does that when setting the header.
- **`Ksef::Auth::Signer`** — the XAdES-BES enveloped signature for
  `POST /auth/xades-signature`, built on Nokogiri and stdlib `openssl` with no new
  dependency. Every algorithm is from the Ministry's published allow-list, and the shape is
  corroborated against both official clients. Its specs recompute each digest and verify
  the `SignatureValue` **without reusing any of the signer's own code**, so a test cannot
  pass by agreeing with a bug; they also assert that tampering with the payload, the
  signing time, or the signature itself is detected, and that the result validates against
  the pinned xmldsig schema.

  It signs a String and returns a String on purpose. A digest over "the document" has to
  match what the verifier computes after parsing the bytes sent, and Nokogiri pretty-prints
  on output without adding text nodes to the tree — so an in-memory tree and its serialised
  form can canonicalise differently. Output is emitted with `FORMAT` off; re-indenting after
  signing would invalidate every signature while leaving it internally consistent.
- **`Ksef::Auth::SignatureTemplate`** and **`Ksef::Auth::Xades`** — the signature XML and
  the algorithm vocabulary, split out so that rendering and cryptography are separable.
- **`Ksef::Auth::TokenRequest`** — the `AuthTokenRequest` document, step 2 of the
  authentication flow. Sends the **2.0** namespace by default, validates the challenge
  format locally
  before a signature is spent on it, and emits the `ContextIdentifier` choice and the
  optional `AuthorizationPolicy` in schema order regardless of the caller's argument
  order. A spec compares the generated document against upstream's own pinned example,
  canonicalised, so the implementation is tied to an artifact rather than to a reading of
  one.
- **`Ksef::Auth::AuthorizationPolicy`** — the client-IP whitelist as its own value object,
  since the schema treats it as a distinct structure with its own rules (three list kinds,
  each capped at ten, fixed order, mandatory `AllowedIps` wrapper). IP *values* are left
  to the schema rather than re-validated in Ruby, which would mean maintaining a second
  and divergent source of truth.
- Pinned the **W3C xmldsig and ETSI XAdES v1.3.2/v1.4.1 schemas** that upstream
  redistributes in its PEF bundle, so the signature namespaces come from an artifact
  rather than from memory. All three compile offline — their imports are relative, so
  unlike the FA(3) schema they need no `schemaLocation` rewrite — which means the signer
  will get real structural validation. Kept under `spec/fixtures/`, not `lib/`: validating
  a signature is a test-time concern, and these are W3C/ETSI documents whose terms are not
  the repository's MIT licence that §1.2 relied on for bundling the FA schemas.
- **`Ksef::Auth::Validator`** — offline XSD validation for auth documents, mirroring
  `Ksef::FA3::Validator`. Validates a document in either namespace, taking the rules from
  v2.1's file with its target namespace rewritten in memory, because v2.0's file cannot be
  compiled at all. A namespace that is not a known schema version is refused rather than
  validated against itself.
- **`Ksef::FA3.build` — the keyword DSL of DESIGN.md §8.** That section's snippet now runs
  verbatim and produces schema-valid FA(3) XML, so the README's headline example is no
  longer aspirational. The DSL accepts the English shorthand from the spec (`qty:`,
  `vat:`) alongside the canonical names, and coerces an address given as a Hash or as an
  already-formatted String. It is a thin front end over the existing value objects —
  every computation and every schema default stays in `Invoice`, so there is one
  implementation of each rule rather than two.

  Unknown or misspelled keys **raise**, naming what was permitted, on the same reasoning
  as the serializer's treatment of unknown element names: the alternative is an invoice
  that is silently missing a field. Passing both a shorthand and its canonical name
  (`qty:` and `quantity:`) is an error rather than a silent last-one-wins. Single-value
  fields set twice do take the later value, which is what a builder should do.
- **Pinned the normative subset of upstream's prose documentation** (`docs/upstream/`, 19
  files) plus the UPO schema and its six worked examples, all at the same
  `CIRFMF/ksef-api@1c34fe27` already used for the OpenAPI contract and FA schemas. The
  repository holds 77 files and only 4 had been pinned; most of what the ledger listed as
  "unverified" turned out to be documented prose nobody had read. Newly ledgered from
  first-tier sources: crypto parameters, XAdES signature requirements, online session
  semantics, the UPO format, per-endpoint rate limits, size limits, and the KSeF number
  structure. Four of the five open items in `docs/REFERENCE.md` §9 are now closed,
  including both that were marked as blocking.
- `docs/REFERENCE.md` §14 — a new section for **contradictions within upstream's own
  sources**, kept separate from §7's divergences from this project's design document. Four
  are recorded, each with the resolution and the evidence for it.
- `spec/openapi_contract_spec.rb` — asserts the ledger's claims against the pinned
  contract, rather than only that the contract has not changed. It covers the two findings
  that had **no code when they were ledgered** — §14.1's discrete IV field, since
  implemented by `Ksef::Crypto`, and §14.2's pre-signed link, since implemented by `Ksef::UPO::Client` — because
  those are the ones that would otherwise rot unnoticed until someone implemented crypto
  or session handling from a stale conclusion.
- Coverage is now gated on three criteria rather than one, at **line 99, branch 95,
  method 100**. Branch coverage was 83% behind 99% line coverage, so seventeen conditional
  paths were untested; closing the real gaps brought it to 97%, and line coverage to 100%. Fixes uncovered on the way:
  proxy configuration was entirely unexercised, and the `Retry-After` parser's past-date
  and unparseable-value fallbacks had no tests. (Branch was ratcheted to 96 and then 97 on 2026-08-24; `spec/spec_helper.rb` is the gate that decides.)

### Changed

- The challenge format check moved from `Auth::TokenRequest::CHALLENGE_FORMAT` to
  **`Auth::Challenge::FORMAT`**, with `Challenge.validate_format!` alongside it. Both
  authentication methods consume the same challenge, so the XAdES document and the
  KSeF-token JSON body would otherwise have carried their own copies of one rule.
- **`bigdecimal` constraint widened from `~> 3.1` to `>= 3.1, < 5`.** The old constraint
  made this gem uninstallable alongside bigdecimal 4, which has been out since 2026-03.
  A library should not force that choice on its users over an arithmetic dependency.
- **Certificate/XAdES authentication moved from 0.3 into 0.1.** A KSeF token can only be
  issued after a one-time XAdES authentication, so a token-only client cannot bootstrap a
  credential from nothing.
- The prior-art claim in DESIGN.md §1 ("there is no Ruby SDK") is withdrawn: `ksef-rb`
  exists and is a working KSeF 2.0 client. This gem's distinction is FA(3) authoring and
  validation rather than transport alone.

### Fixed

- **VAT rate code `3` reported into the wrong summary bucket.** Buckets pair a current rate with
  the one it replaced — 23/22, 8/7, 4/3 — and bucket 5 is not a rate bucket at all: `P_14_5` is
  *"kwota podatku od wartości dodanej"*, foreign VAT under the OSS procedure, whose per-line rate
  lives in `P_12_XII`. Mapping `3` there meant a domestic 3% sale was declared as OSS foreign VAT,
  on a document the XSD accepts. Found by comparing against `ksef-pdf-generator`, the only
  official code that renders these buckets (`docs/REFERENCE.md` §8.1a).

- **`Ksef::FA3.parse` refused a valid document for the wrong reason.** Keyword arguments evaluate
  in source order, so the row reader ran before the invoice-type check — and the Ministry's
  collective corrections carry no `FaWiersz` at all, so a `KOR` was rejected with "Invoice has no
  FaWiersz rows". True, and the wrong diagnosis. The type is now checked first, and a row priced
  gross (`P_9B`/`P_11A` under art. 106e ust. 7-8) is named as such rather than reported as
  missing a net value.

- **Two failures from the first live nightly** (2026-08-24), both ours rather than the
  service's. An integration spec asserted `be_success` on a deliberately duplicated invoice —
  a contradiction, since `440` is a terminal rejection; KSeF behaved exactly as
  `docs/REFERENCE.md` §12.1 describes, returning the original's `originalKsefNumber`. And
  **`Ksef::UPO::Validator` reported an error on every real UPO**: a genuine one is
  XAdES-signed by the Ministry, `upo-v4-3.xsd` declares no `ds:Signature`, and **none of
  upstream's six published examples is signed** — so nothing offline could reveal it. The
  signature is now removed from a copy before the schema runs, which leaves §14.3's warning
  and every other violation intact, and `UPO::Validator.signed?` tells the two kinds of
  document apart (§14.7).

- **Summary buckets are accumulated, not overwritten.** Several VAT rate codes report into one
  bucket — `"23"` and `"22"` both into `P_13_1`/`P_14_1`, `"np I"` and `"np II"` into `P_13_8`
  (`docs/REFERENCE.md` §8.1a) — and assigning per rate code let the last one win. An invoice
  with a 23% line of 100 and a 22% line of 200 emitted `P_13_1=200.00` and `P_14_1=44.00`
  while `P_15` carried the correct `367.00`: the tax base understated by a third,
  `P_13_1 + P_14_1 ≠ P_15`, and **XSD-valid**, because a schema cannot see an arithmetic
  inconsistency. This affected documents the builder produced, not only parsed ones.

- **`Ksef::FA3::Validator` no longer passes XML that is not well-formed.** libxml2 parses in
  recovery mode, so an unclosed root or trailing text after it yielded a usable tree that
  validated clean; `document.errors` was never consulted. Well-formedness is KSeF's first
  admission rule (§15.1).

- **`Data#with` now re-runs the constructor** (`Ksef::FA3::Canonical`). On Ruby 3.2 — this
  gem's declared floor — `Data#with` does *not* call a custom `initialize`, though it does on
  4.0, so every "canonicalise on the way in" invariant was bypassable through a public method
  there: `line.with(quantity: 0.1)` stored a `Float` in a monetary field, straight through the
  no-`Float` rule. RuboCop cannot see this; only running on 3.2 finds it.

- **Amounts and quantities are rounded to the scale their element permits**, at construction.
  `TKwotowy` is `fractionDigits="2"` and `TIlosci` is `"6"`, so a unit price of `150.125` is
  not a value FA(3) can express — and a quantity finer than six places made the document
  schema-invalid outright. Rounding on the way in means the model reports the figure the
  document will carry, and a line's net agrees with the price shown on the invoice.

- **`Formatting.decimal` no longer truncates a large `Rational`.** `BigDecimal`'s second
  argument is *significant digits*, not decimal places; the old `AMOUNT_SCALE + 10` turned
  `12345678901234.56` into `12345678901200.0` — the silent-rounding failure the `Float` ban
  exists to prevent, in the one type admitted as safe.

- **Malformed dates and numbers raise `Ksef::ValidationError`** instead of `Date::Error` and
  `ArgumentError`, so rescuing this gem's own hierarchy — which its docs tell you to do —
  actually catches the empty and malformed field text a rejected document contains.

- **`P_7` and `Podmiot2/Adres` are optional**, as the XSD says (`minOccurs="0"`; the address is
  *"opcjonalne dla przypadków określonych w art. 106e ust. 5 pkt 3"*, the simplified invoice).
  Requiring them refused valid FA(3) while reporting it as malformed. Absent optional row
  fields are now omitted rather than written as empty elements, which failed `TZnakowy512`.

- **`nokogiri` is required centrally.** Every file that uses it required it, but Zeitwerk defers
  loading those files, so the constant did not exist after `require "ksef_client"` until
  something touched the serializer — making one spec pass or fail on the RSpec seed.

- **`bundle exec rake` was never enforcing the coverage floors.** `rake spec` invokes
  `rspec --pattern spec/**{,/*/**}/*_spec.rb`, and that pattern *value* starts with `spec/` —
  which `spec_helper`'s filtered-run check read as "the user narrowed the run", so it skipped
  `minimum_coverage` on every single `rake`. CI calls `bundle exec rspec` directly and has
  always been strict, so nothing shipped uncovered; but CLAUDE.md described `rake` as
  mirroring CI, and on the one criterion that matters most it was strictly weaker.

  Fixed by stripping `--pattern` and its value before looking for selectors, and verified
  both ways: `rake` now fails on a shortfall, and a filtered run stays exempt — which is what
  keeps the nightly's `rspec --tag integration` from failing on coverage rather than on tests.

  It hid because a coverage failure prints among the RuboCop lines, so reading output instead
  of exit codes conceals it. CLAUDE.md now says to check `rake`'s exit code.
- **Authentication status code `480` was missing.** "Uwierzytelnienie zablokowane" — the
  authentication is blocked on suspicion of a security incident, and the user must contact
  the Ministry. `Ksef::Auth::Status` now names it and says so; before, it fell through to
  "unrecognised status code 480".

  The cause is worth recording, because it is a precedence mistake rather than an oversight.
  `docs/REFERENCE.md` §4.8 had sourced the whole table from `ksef-client-csharp`'s enum, on
  the strength of upstream *prose* saying the full list "will be available in the endpoint's
  technical documentation". The pinned OpenAPI contract — a **first-tier** artifact — states
  the table in full, and carries a code the C# enum does not. Two smaller corrections came
  out of the same reading: `450` collapses **eight** distinct causes rather than four, and
  `400`/`401` are C#-only and not contract codes at all. Now asserted in
  `spec/openapi_contract_spec.rb` so the provenance cannot regress silently.

  The general lesson, now in §4.8: when upstream prose says a fact is undocumented, read the
  OpenAPI descriptions before reaching for a reference implementation.
- **A documentation-consistency pass over the whole repo**, which found no defect that would
  fail a live request but a good deal of drift worth correcting. The notable ones:
  `rake auth:bootstrap` told the operator to store a live KSeF credential as a *repository*
  secret, which is precisely what §6a.3 argues against; the coverage floors existed in three
  places with three different values, one of which would have told a contributor they passed
  when CI fails them; SECURITY.md promised a cassette-scanning spec that did not exist;
  DESIGN.md still instructed the reader to send the 2.1 auth namespace and to take token
  expiry from the JWT `exp` claim, both since ruled against; and `docs/errors.md` was missing
  `Ksef::CryptoError` entirely.

  Also corrected: several documents claimed the certificate flow's live verification covered
  more endpoints than it did. Only four have ever reached KSeF — challenge,
  `xades-signature`, `GET /auth/{ref}` and `redeem`. **`refresh` is implemented but has never run
  live** (`ksef-token` has, as of 2026-08-24), and the ledger now says so where it previously
  claimed "the whole §4.2 flow works as ledgered".
- **`spec/cassette_hygiene_spec.rb`** — scans every committed VCR cassette for `Bearer `
  headers and for any value held in `KSEF_TEST_TOKEN` / `KSEF_TEST_NIP`, finding them by
  content rather than by path so one saved somewhere unconventional is still caught. No
  cassette exists yet, so it passes vacuously — which is the point of adding it now, since
  SECURITY.md was already promising users that this check ran.
- `spec.files` globbed only the FA(3) schema directory, so schemas added elsewhere under
  `lib/` would not have shipped — a failure that would appear only in the packaged gem.

### Notes

Two further upstream defects found while implementing authentication, both recorded with
evidence in `docs/REFERENCE.md` §14.4. The root cause is shared: **XML Schema regular
expressions are implicitly anchored, and `^` / `$` are literal characters, not anchors.**

- **Neither official client validates the request locally, and both send the 2.0
  namespace.** C# serialises with `XmlSerializer` and no schema; Java marshals with JAXB
  and never calls `setSchema`. The bundled XSD is a codegen input, not a runtime check, so
  the defects below never fire for them — they emit the real identifier and let the server
  decide. This gem now does the same, and sends 2.0. The Java client even ships its own
  edited copy of the 2.0 schema with the IP patterns repaired but `TNipVatUE` and
  `TPeppolId` left broken, which independently confirms those two are defective.
- **PESEL is a structured identifier and KSeF enforces it** (§6a.3) — the first fact in the
  ledger whose source is the API's own behaviour rather than a document or a reference
  client. A checksum-perfect PESEL was rejected with `400 [21405] Invalid PESEL format`;
  the first six digits encode a birth date with the century folded into the month field.
  Nothing upstream states this, and no amount of offline verification would have found it.
- **A missing OpenSSL CA bundle looks like a broken server certificate** (§6a.5). Recorded
  because the error names the wrong thing entirely and the tempting fix — disabling
  verification — is a hard-rule violation.
- **The PESEL checksum is now recorded** at §6a.3 — needed to invent a test person, and
  confirmed the way §6a.1 confirmed the NIP algorithm: it validates every PESEL the
  upstream documentation ships and rejects those values with the check digit altered.
  §6a.3 also states the NIP check digit precisely, because it is easy to get backwards —
  it *is* the weighted sum `mod 11`, not `11 - (sum mod 11)`.
- **The authentication status codes are now recorded** at `docs/REFERENCE.md` §4.8, from
  the reference implementation — the Ministry's prose names only two of the twelve and says
  the rest "will be available in the endpoint's technical documentation". This narrows, but
  does not close, the open error-code catalogue in §9.
- **A signed `AuthTokenRequest` can never be schema-valid.** The API requires an enveloped
  signature; the schema defining the document declares a closed sequence with no
  `xsd:any`, so that signature is an unexpected element. Both requirements are upstream's
  and they contradict each other. `Signer#sign` therefore validates *before* signing by
  default, which also catches a malformed document before a signature is spent on it.
- **`schemat_auth_v2-0.xsd` does not compile as a schema at all.** Its IP patterns use
  `\b`, which XSD regex has no concept of, so libxml2 rejects the whole file rather than
  those facets. Anyone validating against v2.0 gets a compilation failure, not a
  validation result. Only v2.1 is usable, and it rewrote all three patterns correctly.
- **Two of v2.1's four context identifiers cannot hold their real values.** `TPeppolId`'s
  pattern is written `^P[A-Z]{2}[0-9]{6}$`, so it matches only a value that literally
  starts with `^` and ends with `$`; `TNipVatUE`'s ends with a stray `$`. Upstream's own
  documented example value for `NipVatUe` fails the schema that defines it. The natural
  value is emitted regardless and local validation is reported as advisory for those two
  types — a KSeF token can only be issued in a `Nip` or `InternalId` context anyway, and
  both of those validate cleanly.

Three upstream inconsistencies found while pinning the documentation, each of which would
have produced a working-looking client that fails in practice. All are recorded with
evidence in `docs/REFERENCE.md` §14.

- **The AES initialisation vector is not prefixed to the ciphertext**, despite
  `sesja-interaktywna.md` saying it is. The pinned OpenAPI contract carries the IV as a
  discrete `EncryptionInfo.initializationVector` field, and both the C# and Java reference
  clients emit bare ciphertext. Following the prose yields payloads KSeF cannot decrypt.
- **All six of upstream's UPO examples fail upstream's own UPO schema**, each with the same
  single error: `NazwaPodmiotuPrzyjmujacego` is `fixed="Ministerstwo Finansów"` in the XSD,
  but TEST issues `"Ministerstwo Finansów - środowisko testowe (TE)"`. A client that
  strictly validates a received UPO would reject every UPO that TEST issues.
- **`upo.pages[].downloadUrl` is a pre-signed storage link, not a path to join.** The
  contract declares it `format: uri`, generated per status query, expiring at
  `downloadUrlExpirationDate`, **exempt from API rate limits**, and served with an
  `x-ms-meta-hash` SHA-256 integrity header — and says the access token must *not* be sent
  to it. Both reference clients implement it that way; C# passes `token: null` explicitly.
  Given how tight the session budgets are, this unmetered path is the better default, with
  `GET /sessions/{ref}/upo/{upoRef}` as the fallback once a link expires.

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
