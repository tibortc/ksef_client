# frozen_string_literal: true

require "nokogiri"

# Generator for `docs/field_mapping.md` — the English↔Polish field table DESIGN.md §7.2 owes
# accountants and auditors.
#
# Development-only: this file lives outside `lib/` so it is never packaged, following
# `tasks/fa3_generator.rb`.
#
# ## Why it is generated, and what "declared mapping" buys
#
# §7.2 requires generation "from a declared mapping rather than hand-written, or it will
# drift". {MODELS} below is that declaration — the *only* hand-written part — and everything
# an accountant actually reads (the XSD type, the cardinality, the Ministry's own Polish
# description) is looked up from the pinned schema at generation time.
#
# Three checks make drift loud rather than silent, and they are the point of the exercise:
#
#   1. **Every declared element path is resolved against the schema**, using the serializer's
#      own {Ksef::FA3::Serializer.child_type_key} so a path can only be valid here if it is
#      valid there. A typo, or an element a schema revision removes, aborts the run.
#   2. **Every declared attribute must be a member of its model class.** A rename aborts.
#   3. **Every member of every mapped model must be accounted for** — mapped, or listed in
#      {UNMAPPED} with a reason. Adding a field to a model without saying where it goes aborts.
#
# So the table cannot quietly fall behind the code or the schema; it can only fail to build.
module Fa3FieldMapping
  SCHEMA = "lib/ksef/fa3/schema/schemat_FA(3)_v1-0E.xsd"
  OUT = "docs/field_mapping.md"
  ROOT = "Faktura"

  # Model attributes that no single element path describes. **`element:` is not always nil** —
  # the first version labelled every one of these "Not an element", which was false for three
  # of the five: `buyer_id`, `stated_gross` and `buckets` all reach elements, just not through
  # one row of a one-path-per-attribute table.
  UNMAPPED = {
    "Invoice#rounding" => {
      element: nil,
      why: "**Not in the document at all.** Which rounding strategy produced the summaries is " \
           "inferred when parsing (`RoundingInference`); FA(3) never states it."
    },
    "Invoice#raw_document" => {
      element: nil,
      why: "**Not an element.** Provenance rather than content — the retained source document, " \
           "excluded from this invoice's identity."
    },
    "Invoice#stated_gross" => {
      element: "`P_15`",
      why: "The same `P_15` that `#gross_total` writes, carried only when the document's " \
           "figure differs from what the rows derive. Not a second element."
    },
    "Totals#buckets" => {
      element: "`P_13_*`, `P_14_*`",
      why: "A Hash **keyed by element name**, so each key is its own element. See " \
           "*Summary buckets* below."
    },
    "TableColumn#type" => {
      element: "`Kol/@Typ`",
      why: "**An attribute, not an element** — the only one in FA(3) carrying an inline " \
           "enumeration (`date`, `datetime`, `dec`, `int`, `time`, `txt`). Required by the " \
           "schema, and the permitted values are read from the generated metadata rather " \
           "than restated (`docs/REFERENCE.md` §18.2)."
    },
    "Seller#buyer_id" => {
      element: nil,
      why: "**Buyer-only.** `TPodmiot1` declares no `IDNabywcy`; see the buyer section."
    },
    "Seller#local_government_unit" => {
      element: nil,
      why: "**Buyer-only.** `TPodmiot1` declares no `JST`; see the buyer section."
    },
    "Seller#vat_group_member" => {
      element: nil,
      why: "**Buyer-only.** `TPodmiot1` declares no `GV`; see the buyer section."
    }
  }.freeze

  # Readers that compute rather than store. They are not `Data` members, so the model tables
  # cannot see them — and `gross_total` is one of the six mappings DESIGN.md §7.2 names by
  # hand, so leaving them out left that promise unmet.
  DERIVED = [
    ["Invoice#gross_total", "`P_15`", "The total amount due. Read from a stated summary when " \
                                      "there is one, otherwise net + VAT from the rows."],
    ["Invoice#net_total", "`P_13_*` (sum)", "Total net. Stated summary if present, else the sum of the rows."],
    ["Invoice#vat_total", "`P_14_*` (sum)", "Total VAT, by the invoice's `rounding` strategy."],
    ["Invoice#summary_buckets", "`P_13_*`, `P_14_*`",
     "**The way to reach one bucket**: `invoice.summary_buckets[\"P_13_4\"]`. All seven types."],
    ["Invoice#net_by_rate", "—", "Net per `P_12` rate code, before bucketing. Several codes share a bucket."],
    ["Invoice#vat_by_rate", "—", "VAT per rate code."],
    ["Invoice#unmapped_elements", "—", "For a parsed invoice, the element paths `#to_xml` would drop."],
    ["Invoice#errors", "—", "Validator tiers 1a, 1b and 2. Empty means the document is well-formed and schema-valid."],
    ["Invoice#warnings", "—", "Tier 3, advisory: figures the document states that do not reconcile."],
    ["Line#net", "`P_11`", "The row's net — **read from `P_11` when stated**, else quantity × unit price. " \
                           "nil when the row states no amount, which is legal."],
    ["Line#vat", "—", "Tax on the row, from its rate code. nil when the row states no amount."],
    ["Line#gross", "—", "net + VAT, or nil."],
    ["Totals#net", "`P_13_*` (sum)", "Sum of the stated net buckets."],
    ["Totals#vat", "`P_14_*` (sum)", "Sum of the stated tax buckets."]
  ].freeze

  # One column header, used everywhere the Ministry's own text appears — and **only** where it
  # appears. The first version put our English notes into this column for the rows that have no
  # single element, so a reader met two languages under one heading with no way to tell which
  # sentences were the Ministry's and which were ours. That is worse than it sounds in a
  # document whose whole claim is that the Polish is quoted rather than paraphrased.
  OPIS = "The Ministry's description (Polish, verbatim)"

  DERIVED_INTRO = "These are methods, not stored fields, and for several elements they are what " \
                  "you actually read. **`P_15` is here, not in the Invoice table** — on a `VAT` " \
                  "invoice nothing stores it."

  ANNOTATIONS_INTRO = "`Invoice#annotations` is a Hash keyed by element name, and these eight " \
                      "are the declarations it carries. Each has tax consequences, and the " \
                      "parser **reads them rather than defaulting them** — emitting the defaults " \
                      "regardless would silently deny every declaration an invoice made."

  BUCKETS_INTRO = "`Totals#buckets` is keyed by element name, and `Invoice#summary_buckets` " \
                  "returns the same shape for every invoice type. Which bucket a row lands in " \
                  "is decided by its `P_12` rate code, and **the map is not invertible** — " \
                  "several codes share one bucket. Three buckets have no rate code at all, " \
                  "which is a limit of this model rather than of FA(3): a document may state " \
                  "them, and this model will read and re-write them only as part of a stated " \
                  "summary."

  ABSENT_INTRO = "Listed rather than omitted, because an absent row would otherwise read as " \
                 "\"not supported\" when it may only mean \"not modelled\". A document carrying " \
                 "any of these still parses; `Invoice#unmapped_elements` names exactly what " \
                 "`#to_xml` would drop for a given document, and `#raw_document` keeps the " \
                 "original."

  INDEX_INTRO = "The reverse direction: an element from a Polish invoice, and the attribute " \
                "that carries it. An element listed twice is carried by two different models — " \
                "`P_9A` on an invoice row and `P_9AZ` on an order position are different elements."

  PREAMBLE = <<~HEADER
    <!-- GENERATED by `rake fa3:field_mapping` from FA(3) %<version>s — DO NOT EDIT. -->

    # FA(3) field mapping

    Every field this gem's model carries, and the FA(3) element it reads and writes.

    **Generated**, not written: attribute names come from the model classes, and element names,
    types, cardinalities and descriptions from the pinned XSD. Edit `tasks/field_mapping.rb`
    rather than this file — a declared element that does not exist in the schema fails the
    build rather than appearing here, and a model field nobody has mapped fails it too.

    **One language per column.** The *Ministry's description* column is the Ministry's own
    `xsd:documentation`, in Polish, **complete, unabridged and quoted rather than translated** —
    only runs of whitespace are collapsed. Nothing this project wrote appears in it: our own
    remarks are in *Notes*, in English, and every heading and column label is English too.
    Several descriptions are long, and several say different things for a correction than for
    an ordinary invoice — that is exactly why they are quoted whole.

    The Polish is not translated because it is the operative text: it carries statutory
    citations, and a paraphrase of a tax rule is a different tax rule. **Field-name truth is
    the XSD**, not this table.

    "Required?" is **effective** cardinality: an element inside an optional group is optional
    however it declares itself, and a branch of a choice is never required on its own.

    Section references such as (§8.4) are to `docs/REFERENCE.md`, which ships with this gem.
  HEADER

  FOOTER = <<~FOOTER
    ---

    *Schema: `%<schema>s`. Regenerate with `rake fa3:field_mapping`; `rake fa3:verify` fails if
    this file is stale.*
  FOOTER

  # **The declared mapping.** Paths are from the `Faktura` root; a nil path means the entry is
  # explained in {UNMAPPED}. Order within a model follows the model, not the schema — the
  # schema order is what `Generated::Types` holds and what the serializer emits.
  MODELS = [
    {
      model: "Ksef::FA3::Invoice",
      title: "Invoice",
      intro: "The document itself. `Faktura` in the schema; its scalar fields live under " \
             "`Fa`, its parties directly under the root.",
      fields: [
        %w[attachment Faktura/Zalacznik],
        %w[number Faktura/Fa/P_2],
        %w[issue_date Faktura/Fa/P_1],
        %w[currency Faktura/Fa/KodWaluty],
        %w[invoice_type Faktura/Fa/RodzajFaktury],
        %w[issued_at Faktura/Naglowek/DataWytworzeniaFa],
        %w[seller Faktura/Podmiot1],
        %w[buyer Faktura/Podmiot2],
        ["lines", "Faktura/Fa/FaWiersz", "A true container: everything a line writes is under it."],
        # Representative elements: `correction`, `totals`, `order` and `advances` are each a
        # group rather than one element, so the row names the member that is mandatory once
        # the group is present, and the group's own section below lists the rest.
        %w[annotations Faktura/Fa/Adnotacje],
        ["correction", "Faktura/Fa/DaneFaKorygowanej",
         "**A group, not one element.** The attribute also writes `PrzyczynaKorekty`, " \
         "`TypKorekty`, `OkresFaKorygowanej`, `NrFaKorygowany`, `Podmiot1K`, `Podmiot2K`, " \
         "`P_15ZK` and `KursWalutyZK` as siblings; this is the one that is mandatory once any " \
         "of them is present. See the Correction section."],
        ["totals", "Faktura/Fa/P_15",
         "**The buckets are the substance**, and they are listed under Summary buckets. Note " \
         "`P_15` is written for every invoice, whether or not a summary is stated — see " \
         "`#gross_total` under Computed readers."],
        %w[order Faktura/Fa/Zamowienie],
        %w[advances Faktura/Fa/FakturaZaliczkowa],
        ["rounding", nil],
        ["raw_document", nil],
        ["stated_gross", nil]
      ]
    },
    {
      model: "Ksef::FA3::Subject", key: "Seller",
      title: "Subject as the seller — `Podmiot1`",
      intro: "**The seller and the buyer are different XSD types**, `TPodmiot1` and " \
             "`TPodmiot2`, and they disagree about what is required — so they get a section " \
             "each rather than one section with a footnote. A seller must state a name and an " \
             "address; a buyer need not. `Podmiot1K` on a correction uses this type.",
      fields: [
        %w[nip Faktura/Podmiot1/DaneIdentyfikacyjne/NIP],
        %w[name Faktura/Podmiot1/DaneIdentyfikacyjne/Nazwa],
        %w[address Faktura/Podmiot1/Adres],
        ["local_government_unit", nil],
        ["vat_group_member", nil],
        ["buyer_id", nil]
      ]
    },
    {
      model: "Ksef::FA3::Subject", key: "Buyer",
      title: "Subject as the buyer — `Podmiot2`",
      intro: "`Podmiot2`, and `Podmiot2K` on a correction. **The buyer's name and address are " \
             "both optional** — a fact this project got wrong three times before (§8.2a) — and " \
             "the identity is a four-way choice of which this model carries only the NIP branch.",
      fields: [
        %w[nip Faktura/Podmiot2/DaneIdentyfikacyjne/NIP],
        %w[name Faktura/Podmiot2/DaneIdentyfikacyjne/Nazwa],
        %w[address Faktura/Podmiot2/Adres],
        %w[local_government_unit Faktura/Podmiot2/JST],
        %w[vat_group_member Faktura/Podmiot2/GV],
        %w[buyer_id Faktura/Podmiot2/IDNabywcy]
      ]
    },
    {
      model: "Ksef::FA3::Address",
      title: "Address",
      intro: "FA(3) has no street/city/postcode fields: it takes two free-text lines. " \
             "`Address` composes them at construction and keeps the composed form (§8.2b), " \
             "so `street`/`city`/`postal_code` are constructor sugar rather than attributes.",
      fields: [
        %w[line1 Faktura/Podmiot2/Adres/AdresL1],
        %w[line2 Faktura/Podmiot2/Adres/AdresL2],
        %w[country Faktura/Podmiot2/Adres/KodKraju]
      ]
    },
    {
      model: "Ksef::FA3::Line",
      title: "Line — an invoice row",
      intro: "One `FaWiersz`. Every child but `NrWierszaFa` is optional, so most fields here " \
             "may be absent from a legal document (§8.6).",
      fields: [
        %w[name Faktura/Fa/FaWiersz/P_7],
        %w[unit Faktura/Fa/FaWiersz/P_8A],
        ["quantity", "Faktura/Fa/FaWiersz/P_8B", "Also feeds `P_11` when the row states no net."],
        ["net_unit_price", "Faktura/Fa/FaWiersz/P_9A",
         "`TKwotowy2` — **eight decimal places**, four times the amount it produces. Also " \
         "feeds `P_11` when the row states no net."],
        ["net_amount", "Faktura/Fa/FaWiersz/P_11",
         "**`P_11` has two sources.** Stated here when the row states one; otherwise derived " \
         "from `quantity` × `net_unit_price`. `Line#net` is the reader that answers either " \
         "way, and nil when the row states no amount at all."],
        %w[vat_rate Faktura/Fa/FaWiersz/P_12],
        %w[row_number Faktura/Fa/FaWiersz/NrWierszaFa],
        %w[state_before Faktura/Fa/FaWiersz/StanPrzed]
      ]
    },
    {
      model: "Ksef::FA3::Totals",
      title: "Totals — a stated summary",
      intro: "What a document states rather than what its rows imply. Present on the six " \
             "types in `Invoice::STATED_TOTALS_TYPES`; a `VAT` invoice derives its summary " \
             "instead (§8.4, §8.5).",
      fields: [
        %w[gross Faktura/Fa/P_15],
        ["buckets", nil]
      ]
    },
    {
      model: "Ksef::FA3::Correction",
      title: "Correction",
      intro: "The group that makes a `KOR`, `KOR_ZAL` or `KOR_ROZ` a correction. Optional as " \
             "a whole; `DaneFaKorygowanej` is mandatory once any of it is present (§8.4).",
      fields: [
        %w[reason Faktura/Fa/PrzyczynaKorekty],
        %w[effect Faktura/Fa/TypKorekty],
        %w[corrected Faktura/Fa/DaneFaKorygowanej],
        %w[period Faktura/Fa/OkresFaKorygowanej],
        %w[corrected_number Faktura/Fa/NrFaKorygowany],
        %w[previous_seller Faktura/Fa/Podmiot1K],
        %w[previous_buyers Faktura/Fa/Podmiot2K],
        %w[paid_before Faktura/Fa/P_15ZK],
        %w[exchange_rate_before Faktura/Fa/KursWalutyZK]
      ]
    },
    {
      model: "Ksef::FA3::CorrectedInvoice",
      title: "CorrectedInvoice — which invoice is corrected",
      intro: "One `DaneFaKorygowanej`. Its choice group names the corrected invoice either " \
             "by KSeF number or by number-and-date, and the branches are not symmetrical " \
             "with `FakturaZaliczkowa`'s (§8.5).",
      fields: [
        %w[number Faktura/Fa/DaneFaKorygowanej/NrFaKorygowanej],
        %w[issue_date Faktura/Fa/DaneFaKorygowanej/DataWystFaKorygowanej],
        %w[ksef_number Faktura/Fa/DaneFaKorygowanej/NrKSeFFaKorygowanej]
      ]
    },
    {
      model: "Ksef::FA3::Order",
      title: "Order — an advance invoice's order",
      intro: "`Zamowienie`, which replaces `FaWiersz` entirely on a `ZAL`. " \
             "`WartoscZamowienia` is the whole order **including tax** (§8.5).",
      fields: [
        %w[total Faktura/Fa/Zamowienie/WartoscZamowienia],
        %w[lines Faktura/Fa/Zamowienie/ZamowienieWiersz]
      ]
    },
    {
      model: "Ksef::FA3::Attachment",
      base: "Faktura/Zalacznik",
      title: "Attachment — the invoice attachment",
      intro: "`Zalacznik`, a **sibling of `Fa`** rather than one of its children, so it takes " \
             "part in no summary and no arithmetic. FA(3) carries no bytes and no MIME type: " \
             "an attachment here is a structured document of headings, key/value metadata, " \
             "paragraphs and tables. Operational constraints on sending one are out of 0.1 " \
             "scope (DESIGN.md §7.4).",
      fields: [
        %w[blocks Faktura/Zalacznik/BlokDanych]
      ]
    },
    {
      model: "Ksef::FA3::DataBlock",
      base: "Faktura/Zalacznik/BlokDanych",
      title: "DataBlock — one block of an attachment",
      intro: "`BlokDanych`. `MetaDane` is the one child the schema requires, which is why a " \
             "block describing itself only with a heading or a table is refused at " \
             "construction.",
      fields: [
        %w[heading Faktura/Zalacznik/BlokDanych/ZNaglowek],
        %w[metadata Faktura/Zalacznik/BlokDanych/MetaDane],
        %w[paragraphs Faktura/Zalacznik/BlokDanych/Tekst/Akapit],
        %w[tables Faktura/Zalacznik/BlokDanych/Tabela]
      ]
    },
    {
      model: "Ksef::FA3::MetaEntry",
      base: "Faktura/Zalacznik/BlokDanych/MetaDane",
      title: "MetaEntry — one key/value pair",
      intro: "`MetaDane` on a block and `TMetaDane` on a table are the same shape under " \
             "different names, so one class serves both. Mapped against the block's names; " \
             "the table's are `TKlucz`/`TWartosc`.",
      fields: [
        %w[key Faktura/Zalacznik/BlokDanych/MetaDane/ZKlucz],
        %w[value Faktura/Zalacznik/BlokDanych/MetaDane/ZWartosc]
      ]
    },
    {
      model: "Ksef::FA3::AttachmentTable",
      base: "Faktura/Zalacznik/BlokDanych/Tabela",
      title: "AttachmentTable — a table inside a block",
      intro: "`Tabela`. **Rows are ragged**: `Kol` and `WKom` each repeat 1..20 and the schema " \
             "ties them together nowhere, so a row need not carry one cell per column — both " \
             "Ministry samples alternate one-cell label rows with full-width ones.",
      fields: [
        %w[metadata Faktura/Zalacznik/BlokDanych/Tabela/TMetaDane],
        %w[caption Faktura/Zalacznik/BlokDanych/Tabela/Opis],
        %w[columns Faktura/Zalacznik/BlokDanych/Tabela/TNaglowek/Kol],
        ["rows", "Faktura/Zalacznik/BlokDanych/Tabela/Wiersz",
         "An Array of rows, each an Array of `WKom` cells (1–20, and **ragged** — a row need " \
         "not carry one per column)."],
        %w[totals Faktura/Zalacznik/BlokDanych/Tabela/Suma/SKom]
      ]
    },
    {
      model: "Ksef::FA3::TableColumn",
      base: "Faktura/Zalacznik/BlokDanych/Tabela/TNaglowek/Kol",
      title: "TableColumn — one column heading",
      intro: "`Kol`. Its `Typ` attribute is FA(3)'s **only** inline attribute enumeration, and " \
             "the six permitted values are read from the generated metadata rather than " \
             "restated in Ruby (`docs/REFERENCE.md` §18.2).",
      fields: [
        %w[name Faktura/Zalacznik/BlokDanych/Tabela/TNaglowek/Kol/NKom],
        ["type", nil]
      ]
    },
    {
      model: "Ksef::FA3::OrderLine",
      title: "OrderLine — an order position",
      intro: "One `ZamowienieWiersz`. Unlike {Line} nothing here is derived: the document " \
             "states both the net and the tax, so both are read (§8.5).",
      fields: [
        %w[name Faktura/Fa/Zamowienie/ZamowienieWiersz/P_7Z],
        %w[unit Faktura/Fa/Zamowienie/ZamowienieWiersz/P_8AZ],
        %w[quantity Faktura/Fa/Zamowienie/ZamowienieWiersz/P_8BZ],
        %w[net_unit_price Faktura/Fa/Zamowienie/ZamowienieWiersz/P_9AZ],
        %w[net_amount Faktura/Fa/Zamowienie/ZamowienieWiersz/P_11NettoZ],
        %w[vat_amount Faktura/Fa/Zamowienie/ZamowienieWiersz/P_11VatZ],
        %w[vat_rate Faktura/Fa/Zamowienie/ZamowienieWiersz/P_12Z],
        %w[row_number Faktura/Fa/Zamowienie/ZamowienieWiersz/NrWierszaZam],
        %w[state_before Faktura/Fa/Zamowienie/ZamowienieWiersz/StanPrzedZ]
      ]
    },
    {
      model: "Ksef::FA3::AdvanceInvoice",
      title: "AdvanceInvoice — an advance already settled",
      intro: "One `FakturaZaliczkowa` on a `ROZ` or `KOR_ROZ`. Its choice is **inverted** " \
             "from `DaneFaKorygowanej`'s: the marker `NrKSeFZN` pairs with the plain number, " \
             "and the KSeF branch is the number alone (§8.5).",
      fields: [
        %w[number Faktura/Fa/FakturaZaliczkowa/NrFaZaliczkowej],
        %w[ksef_number Faktura/Fa/FakturaZaliczkowa/NrKSeFFaZaliczkowej]
      ]
    }
  ].freeze

  # Resolves an element path against the pinned schema.
  #
  # **It walks the XSD itself, not `Generated::Types`**, and that is the whole point. The
  # generated metadata is *flattened*: it hoists the children of an `xsd:choice` or of a
  # `<xsd:sequence minOccurs="0">` up to their parent, because the serializer only needs to
  # know what order to write things in. A table for auditors needs the opposite — whether a
  # field is **required** — and the flattened view answers that wrong. It reported the buyer's
  # `NIP` and `Nazwa` as mandatory when the first is one branch of a choice and the second sits
  # in an optional sequence, which is the error `docs/REFERENCE.md` §8.2a records as having bit
  # this project three times.
  #
  # Walking the schema also makes the description **path-exact**. Looked up by bare name it had
  # to be dropped whenever a name is declared more than once with different wording — eleven
  # names are — so `Adres` and `KodKraju` came back blank. There is no ambiguity once you know
  # which declaration you are standing on.
  class Schema
    XSD_NS = { "xsd" => "http://www.w3.org/2001/XMLSchema" }.freeze

    def initialize(path: SCHEMA)
      @document = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
    end

    # @return [Hash] `{name:, type:, occurs:, documentation:}` for the element the path names
    # @raise [RuntimeError] if any segment does not exist, which is the drift guard
    # @param base [String, nil] the model's own element path. Cardinality is reported **relative
    #   to it** — "given a `Tabela`, is there a `Suma`?" — which is what a reader of that
    #   model's section is asking. Without a base only the element's own wrappers count, which
    #   is how the pre-existing sections have always rendered and is left unchanged for them.
    def field(path, base: nil)
      ancestry = ancestry_for(path)
      node = ancestry.last
      between = base.nil? ? [] : ancestry[base.split("/").length...-1].to_a
      { name: node["name"], type: node["type"], occurs: occurs(node, between + [node]),
        documentation: annotation(node) }
    end

    # Every element the type declares, **including those nested in inner sequences and
    # choices** — `P_6` sits in one, and reading only the outer sequence left it named neither
    # in a table nor in the negative list, which is the gap that list exists to close.
    #
    # @return [Array<String>] element names, in document order
    def children_of(path)
      scope = scope_of(node_for(path))
      scope.xpath(".//xsd:element[@name]", XSD_NS)
           .select { |element| owning_type(element) == scope }
           .map { |element| element["name"] }
    end

    # @return [String] e.g. "1-0E", read the same way the codegen reads it
    def version
      @document.at_xpath('//xsd:attribute[@name="wersjaSchemy"]', XSD_NS)&.[]("fixed") ||
        raise("wersjaSchemy not found in #{SCHEMA} — schema shape changed, review this task")
    end

    private

    def node_for(path) = ancestry_for(path).last

    # Every element on the path, root first. The **ancestors matter**: an element is optional
    # when any element above it on the path is, and until 2026-08-26 only the wrappers inside
    # its own complexType were considered. No declared path crossed an optional element until
    # the attachment's did, so `docs/field_mapping.md` printed `paragraphs` as "yes, 1–10" and
    # `totals` as "yes, 1–20" — both live inside optional parents (`Tekst`, `Suma`), and the
    # file's own rule says Required? is *effective* cardinality. Same family as §8.2a: a wrong
    # Required? in a table an auditor reads.
    def ancestry_for(path)
      segments = path.split("/")
      root = @document.at_xpath("//xsd:element[@name='#{segments.first}']", XSD_NS)
      raise "#{path}: no root element #{segments.first.inspect}" if root.nil?

      segments[1..].inject([root]) { |chain, name| chain << child(chain.last, name, path) }
    end

    def child(parent, name, path)
      scope = scope_of(parent)
      found = scope&.xpath(".//xsd:element[@name='#{name}']", XSD_NS)
                   &.find { |element| owning_type(element) == scope }
      found || raise("#{path}: no element #{name.inspect} under #{parent["name"].inspect}")
    end

    # The complexType an element's children live in: declared inline, or referenced by name.
    def scope_of(element)
      inline = element.at_xpath("xsd:complexType", XSD_NS)
      return inline if inline

      named = element["type"].to_s.sub(/\A\w+:/, "")
      @document.at_xpath("//xsd:complexType[@name='#{named}']", XSD_NS)
    end

    # Walked by hand: `Nokogiri::XML::Node#ancestors` takes a CSS selector, and a namespace
    # prefix in one does not resolve, so `ancestors("xsd:complexType")` silently answers [].
    def owning_type(element)
      node = element.parent
      node = node.parent while node && node.name != "complexType"
      node
    end

    # **Effective** cardinality: the element's own `minOccurs`/`maxOccurs` combined with every
    # `xsd:sequence` or `xsd:choice` between it and its complexType. An element inside an
    # optional sequence is optional however it declares itself, and a branch of a choice is
    # never required on its own even when the choice is.
    def occurs(element, ancestry = [element])
      wrappers = wrappers_of(element)
      choice = wrappers.any? { |wrapper| wrapper.name == "choice" }
      optional_parent = ancestry[..-2].any? { |ancestor| optional?(ancestor) }
      {
        min: optional_parent ? 0 : effective_min(element, wrappers, choice),
        max: effective_max(element, wrappers),
        choice: choice
      }
    end

    # An element is optional if it says so, or if a wrapper inside its own type does.
    def optional?(element)
      element["minOccurs"] == "0" ||
        wrappers_of(element).any? { |wrapper| wrapper["minOccurs"] == "0" || wrapper.name == "choice" }
    end

    def effective_min(element, wrappers, choice)
      return 0 if choice || wrappers.any? { |wrapper| wrapper["minOccurs"] == "0" }

      bound(element, "minOccurs", 1)
    end

    def effective_max(element, wrappers)
      wrappers.map { |wrapper| bound(wrapper, "maxOccurs", 1) }.push(bound(element, "maxOccurs", 1)).max
    end

    # Every `xsd:sequence` / `xsd:choice` between the element and its complexType.
    # Stops at the enclosing `complexType` — or at `schema`, for a top-level element such as
    # `Faktura`, which has no enclosing type at all. Without that second stop the walk ran off
    # the top of the tree into the Document, which has no `#parent`.
    def wrappers_of(element)
      found = []
      node = element.parent
      while node.respond_to?(:name) && !%w[complexType schema].include?(node.name)
        found << node
        node = node.parent
      end
      found
    end

    # `"unbounded"` would answer 0 through `to_i`, and FA(3) contains none — but a schema
    # revision that added one would otherwise render a silently wrong bound, so it raises.
    def bound(node, attribute, default)
      value = node[attribute]
      raise "#{node.path}: unbounded #{attribute} — review how this table renders it" if value == "unbounded"

      value.nil? ? default : value.to_i
    end

    def annotation(element)
      text = element.at_xpath("xsd:annotation/xsd:documentation", XSD_NS)&.text
      text&.strip&.gsub(/\s+/, " ")
    end
  end

  # Renders the Markdown.
  class Renderer
    def initialize(schema: Schema.new)
      @schema = schema
    end

    def render
      sections = MODELS.map { |model| section(model) }
      # After the sections, so a broken declaration is reported by the guard that understands
      # it rather than by this one complaining about the reasons it left behind.
      verify_unmapped!
      [preamble, sections, derived_section, annotations_section,
       buckets_section, absent_section, index_section, footer].join("\n")
    end

    # Guard 4. An {UNMAPPED} entry nothing refers to is a leftover from a field that was
    # renamed or mapped, and it would sit here indefinitely explaining an attribute that no
    # longer exists. The other three guards catch declarations without reasons; this catches
    # reasons without declarations.
    def verify_unmapped!
      referenced = MODELS.flat_map do |model|
        prefix = model[:key] || model[:model].split("::").last
        model[:fields].filter_map { |attribute, path| "#{prefix}##{attribute}" if path.nil? }
      end
      orphans = UNMAPPED.keys - referenced
      raise "UNMAPPED entries nothing refers to: #{orphans.inspect}" if orphans.any?
    end

    private

    def section(model)
      verify_members!(Object.const_get(model[:model]), model)
      prefix = model[:key] || model[:model].split("::").last
      rows = model[:fields].map { |attribute, path, note| row(prefix, attribute, path, note, model[:base]) }
      table("## #{model[:title]}", "`#{model[:model]}` — #{model[:intro]}",
            "Attribute | FA(3) element | Type | Required? | #{OPIS} | Notes", rows)
    end

    # Check 2 and check 3, both aborting.
    def verify_members!(klass, model)
      declared = model[:fields].map(&:first).map(&:to_sym)
      missing = declared - klass.members
      raise "#{model[:model]}: declared but not a member: #{missing.inspect}" unless missing.empty?

      unaccounted = klass.members - declared
      raise "#{model[:model]}: member(s) neither mapped nor in UNMAPPED: #{unaccounted.inspect}" if unaccounted.any?
    end

    def row(key_prefix, attribute, path, note = nil, base = nil)
      return unmapped_row(key_prefix, attribute) if path.nil?

      field = @schema.field(path, base: base)
      "| `#{attribute}` | `#{field[:name]}` | #{type_of(field)} | #{required(field[:occurs])} | " \
        "#{field[:documentation] || "—"} | #{note || "—"} |"
    end

    # An element with no `type` attribute has an **anonymous** `complexType` declared inline —
    # `Podmiot1`, `Fa`, `FaWiersz` and `Adnotacje` are all of them. FA(3) names only seven
    # complexTypes, so there is genuinely no type name to print, and inventing one is how
    # `TFaWiersz` came to be asserted in nine files.
    def type_of(field)
      field[:type].nil? ? "*(inline)*" : "`#{field[:type].sub(/\Atns:/, "")}`"
    end

    # Phrased as the question an auditor is asking, rather than as raw occurrence counts.
    def required(occurs)
      return "one of a choice" if occurs[:choice]
      return "**yes**" if occurs[:min].positive? && occurs[:max] == 1
      return "yes, #{occurs[:min]}–#{occurs[:max]}" if occurs[:min].positive?

      occurs[:max] == 1 ? "optional" : "optional, up to #{occurs[:max]}"
    end

    def unmapped_row(key_prefix, attribute)
      key = "#{key_prefix}##{attribute}"
      entry = UNMAPPED.fetch(key) { raise "#{key} has a nil path and no UNMAPPED entry" }
      # The Ministry's column stays empty rather than carrying our prose: one language per
      # column, and this row has no single element whose annotation would belong there.
      "| `#{attribute}` | #{entry[:element] || "—"} | — | — | — | #{entry[:why]} |"
    end

    def table(heading, intro, header, rows)
      ["", heading, "", intro, "", "| #{header} |",
       "|#{"---|" * header.count("|").succ}", *rows, ""].join("\n")
    end

    # Computed readers. They are not `Data` members, so nothing else here would list them —
    # and for several fields they are what a caller actually reads. `gross_total` is one of the
    # six mappings DESIGN.md §7.2 names by hand, and it went missing from the first version of
    # this document for exactly that reason.
    def derived_section
      rows = DERIVED.map { |reader, element, note| "| `#{reader}` | #{element} | #{note} |" }
      table("## Computed readers", DERIVED_INTRO, "Reader | FA(3) element | What it does", rows)
    end

    # `Adnotacje` is eight legal declarations behind one element, and they are what an auditor
    # checks. Rendered like the buckets, for the same reason: a Hash keyed by element name has
    # no attribute to put in the left column.
    def annotations_section
      rows = Ksef::FA3::Invoice::DEFAULT_ANNOTATIONS.keys.map do |name|
        field = @schema.field("Faktura/Fa/Adnotacje/#{name}")
        "| `#{name}` | #{required(field[:occurs])} | #{field[:documentation] || "—"} |"
      end
      table("## Annotations", ANNOTATIONS_INTRO, "Element | Required? | #{OPIS}", rows)
    end

    def buckets_section
      rows = Ksef::FA3::Totals::ELEMENTS.map do |name|
        codes = Ksef::FA3::VatRate::BUCKETS.select { |_, pair| pair.include?(name) }.keys
        field = @schema.field("Faktura/Fa/#{name}")
        "| `#{name}` | #{codes.empty? ? "*(none)*" : codes.map { |c| "`#{c}`" }.join(", ")} " \
          "| #{field[:documentation] || "—"} |"
      end
      table("## Summary buckets", BUCKETS_INTRO, "Element | Rate codes | #{OPIS}", rows)
    end

    # The negative list. DESIGN.md §7.2 deferred this document precisely because a partial one
    # would read as "not supported" rather than "not documented yet" — so it has to say what it
    # does not carry, not merely omit it.
    def absent_section
      rows = %w[Faktura Faktura/Fa].map do |parent|
        absent = @schema.children_of(parent) - mapped_names - carried_indirectly
        "| `#{parent}` | #{absent.map { |name| "`#{name}`" }.join(", ")} |"
      end
      table("## What this model does not carry", ABSENT_INTRO, "Under | Elements", rows)
    end

    def mapped_names
      # **Every segment**, not just the last. A container this model walks through — `Fa`,
      # `Naglowek`, `Podmiot1`, `Adres` — is carried as surely as the leaf inside it, and
      # counting only leaves listed those containers as "not carried".
      #
      # `fields[1]`, never `.last`: a row may carry a third element, its English note, and
      # taking the last of a three-element tuple silently reads the note as a path.
      MODELS.flat_map { |model| model[:fields].map { |field| field[1] } }
            .compact.flat_map { |path| path.split("/") }.uniq
    end

    # Named elsewhere in the document rather than in a model's own row.
    def carried_indirectly
      Ksef::FA3::Totals::ELEMENTS + Ksef::FA3::Invoice::DEFAULT_ANNOTATIONS.keys + %w[Adnotacje]
    end

    # Polish element to English attribute, which is the direction an accountant reads in.
    # **Sorted on the whole pair, not on the element name.** `Enumerable#sort_by` is not stable,
    # and several element names appear twice — `NIP`, `Nazwa` and `Adres` for both the seller
    # and the buyer — so sorting on the name alone left their relative order unspecified. It
    # came out one way on macOS and the other on Linux, which made the committed file stale in
    # CI and green locally: a determinism failure of exactly the kind DESIGN.md §11 makes a
    # definition-of-done gate for codegen.
    def index_section
      rows = index_entries.sort.chunk_while { |a, b| a.first == b.first }.map do |group|
        "| `#{group.first.first}` | #{group.map { |_, reader| "`#{reader}`" }.join(", ")} |"
      end
      table("## Element index", INDEX_INTRO, "FA(3) element | Attribute", rows)
    end

    def index_entries
      MODELS.flat_map do |model|
        prefix = model[:key] || model[:model].split("::").last
        model[:fields].filter_map { |attribute, path| [path.split("/").last, "#{prefix}##{attribute}"] if path }
      end
    end

    def preamble = format(PREAMBLE, version: @schema.version)
    def footer = format(FOOTER, schema: SCHEMA)
  end

  def self.generate!
    File.write(OUT, Renderer.new.render, encoding: "UTF-8")
  end

  # Regenerates and reports whether the committed file was already what a fresh run produces.
  # The same gate `rake fa3:verify` applies to `generated/`, for the same reason: a generated
  # document that nobody regenerates is a hand-written one that lies (DESIGN.md §7.2).
  # **Asks without answering by writing.** The first version called {generate!} and compared
  # before with after, which made a *verify* task repair the thing it was complaining about:
  # a hand edit vanished silently, a second run went green with no human intervention, and the
  # abort message told you to run a task that had already run. Rendering to a String costs
  # nothing and leaves the working tree alone.
  def self.stale?
    return true unless File.exist?(OUT)

    Renderer.new.render != File.read(OUT, encoding: "UTF-8")
  end
end
