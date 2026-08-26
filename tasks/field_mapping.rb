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

  # Model attributes that deliberately reach no element, with the reason shown in the table.
  UNMAPPED = {
    "Invoice#rounding" => "Not in the document at all. Which rounding strategy produced the " \
                          "summaries is inferred on parse (`RoundingInference`), never stated.",
    "Invoice#raw_document" => "Provenance, not content — the retained source document, " \
                              "excluded from identity (§8.2b).",
    "Invoice#stated_gross" => "Carries `Fa/P_15` when it differs from the derived total; it " \
                              "is the same element as `#gross_total` writes, not a second " \
                              "one (§17.2).",
    "Totals#buckets" => "A Hash keyed by element name — `P_13_1`, `P_14_1`, … — so each key " \
                        "*is* its element. See the summary-bucket table below.",
    "Subject#buyer_id" => "`Podmiot2/IDNabywcy` and `Podmiot2K/IDNabywcy` only; a seller has " \
                          "no such element."
  }.freeze

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
        %w[number Faktura/Fa/P_2],
        %w[issue_date Faktura/Fa/P_1],
        %w[currency Faktura/Fa/KodWaluty],
        %w[invoice_type Faktura/Fa/RodzajFaktury],
        %w[issued_at Faktura/Naglowek/DataWytworzeniaFa],
        %w[seller Faktura/Podmiot1],
        %w[buyer Faktura/Podmiot2],
        %w[lines Faktura/Fa/FaWiersz],
        # Representative elements: `correction`, `totals`, `order` and `advances` are each a
        # group rather than one element, so the row names the member that is mandatory once
        # the group is present, and the group's own section below lists the rest.
        %w[annotations Faktura/Fa/Adnotacje],
        %w[correction Faktura/Fa/DaneFaKorygowanej],
        %w[totals Faktura/Fa/P_15],
        %w[order Faktura/Fa/Zamowienie],
        %w[advances Faktura/Fa/FakturaZaliczkowa],
        ["rounding", nil],
        ["raw_document", nil],
        ["stated_gross", nil]
      ]
    },
    {
      model: "Ksef::FA3::Subject",
      title: "Subject — a party",
      intro: "One party. Written as `Podmiot1` (seller), `Podmiot2` (buyer), or their `K` " \
             "twins `Podmiot1K`/`Podmiot2K` on a correction, which state the parties as the " \
             "corrected invoice had them. Paths below use `Podmiot2`.",
      fields: [
        %w[nip Faktura/Podmiot2/DaneIdentyfikacyjne/NIP],
        %w[name Faktura/Podmiot2/DaneIdentyfikacyjne/Nazwa],
        %w[address Faktura/Podmiot2/Adres],
        %w[local_government_unit Faktura/Podmiot2/JST],
        %w[vat_group_member Faktura/Podmiot2/GV],
        ["buyer_id", nil]
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
        %w[quantity Faktura/Fa/FaWiersz/P_8B],
        %w[net_unit_price Faktura/Fa/FaWiersz/P_9A],
        %w[net_amount Faktura/Fa/FaWiersz/P_11],
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

  # Resolves an element path against the pinned schema, and reads its Polish description.
  class Schema
    def initialize(path: SCHEMA)
      @document = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
      @docs = index_documentation
    end

    # @return [Hash] the particle — `{name:, type:, min:, max:}`
    # @raise [RuntimeError] if any segment does not exist, which is the drift guard
    def particle(path)
      segments = path.split("/")
      key = segments.first
      found = nil

      segments[1..].each do |name|
        found = Ksef::FA3::Generated::Types.ordered_elements(key).find { |p| p[:name] == name }
        raise "#{path}: no element #{name.inspect} under #{key.inspect}" if found.nil?

        key = Ksef::FA3::Serializer.child_type_key(key, found)
      end
      found || raise("#{path}: nothing to resolve")
    end

    # The Ministry's own description, when every occurrence of the name agrees. Element names
    # repeat across the schema (`NIP` a dozen times), so where occurrences carry *different*
    # documentation this answers nil rather than guessing which one applies.
    XSD_NS = { "xsd" => "http://www.w3.org/2001/XMLSchema" }.freeze

    def documentation(name) = @docs[name]

    # @return [String] e.g. "1-0E", read the same way the codegen reads it
    def version
      @document.at_xpath('//xsd:attribute[@name="wersjaSchemy"]', XSD_NS)&.[]("fixed") ||
        raise("wersjaSchemy not found in #{SCHEMA} — schema shape changed, review this task")
    end

    private

    def index_documentation
      documented.group_by { |name, _| name }
                .filter_map { |name, pairs| agreed(name, pairs.map(&:last)) }
                .to_h
    end

    # @return [Array<Array(String, String)>] every named element that carries documentation
    def documented
      @document.xpath("//xsd:element[@name]", XSD_NS).filter_map do |element|
        text = annotation(element)
        [element["name"], text] unless text.nil?
      end
    end

    # Only where every occurrence agrees; see {#documentation}.
    def agreed(name, texts) = texts.uniq.size == 1 ? [name, summarise(texts.first)] : nil

    def annotation(element)
      text = element.at_xpath("xsd:annotation/xsd:documentation", XSD_NS)&.text
      text&.strip&.gsub(/\s+/, " ")
    end

    # Some annotations run to a full paragraph of statute — `FaWiersz`'s is nine hundred
    # characters — which is unreadable in a table cell and would push the useful columns off
    # the page. Truncated on a sentence boundary where there is one nearby, with the schema
    # named as the authority for the rest.
    def summarise(text, limit: 220)
      return text if text.length <= limit

      head = text[0, limit]
      cut = head.rindex(". ")
      cut && cut > limit / 2 ? "#{head[0, cut + 1]} […]" : "#{head.rstrip} […]"
    end
  end

  # Renders the Markdown.
  class Renderer
    def initialize(schema: Schema.new)
      @schema = schema
    end

    def render
      [preamble, MODELS.map { |model| section(model) }, buckets_section, footer].join("\n")
    end

    private

    def section(model)
      klass = Object.const_get(model[:model])
      verify_members!(klass, model)

      rows = model[:fields].map { |attribute, path| row(model[:model], attribute, path) }
      ["## #{model[:title]}", "", "`#{model[:model]}` — #{model[:intro]}", "",
       "| Attribute | FA(3) element | Type | Occurs | Ministry's description |",
       "|---|---|---|---|---|", *rows, ""].join("\n")
    end

    # Check 2 and check 3, both aborting.
    def verify_members!(klass, model)
      declared = model[:fields].map(&:first).map(&:to_sym)
      missing = declared - klass.members
      raise "#{model[:model]}: declared but not a member: #{missing.inspect}" unless missing.empty?

      unaccounted = klass.members - declared
      return if unaccounted.empty?

      raise "#{model[:model]}: member(s) neither mapped nor in UNMAPPED: #{unaccounted.inspect}"
    end

    def row(model, attribute, path)
      return unmapped_row(model, attribute) if path.nil?

      particle = @schema.particle(path)
      element = path.split("/").last
      "| `#{attribute}` | `#{element}` | #{type_of(particle)} | " \
        "#{occurs(particle)} | #{@schema.documentation(element) || "—"} |"
    end

    # An element with no `type` attribute has an **anonymous** `complexType` declared inline —
    # `Podmiot1`, `Fa`, `FaWiersz` and `Adnotacje` are all of them. FA(3) names only seven
    # complexTypes, so there is genuinely no type name to print, and inventing one is how
    # `TFaWiersz` came to be asserted in nine files before an audit caught it.
    def type_of(particle)
      particle[:type].nil? ? "*(inline)*" : "`#{particle[:type].sub(/\Atns:/, "")}`"
    end

    def unmapped_row(model, attribute)
      key = "#{model.split("::").last}##{attribute}"
      reason = UNMAPPED.fetch(key) { raise "#{key} has a nil path and no UNMAPPED entry" }
      "| `#{attribute}` | — | — | — | **Not an element.** #{reason} |"
    end

    # `Generated::Types` writes `max: nil` for an unbounded element — **and FA(3) has none**:
    # `maxOccurs="unbounded"` appears zero times in the pinned schema, every repeat being
    # bounded (`FaWiersz` at 10 000, `FakturaZaliczkowa` at 100). So there is no nil branch
    # here, and an earlier draft that compared against the *string* `"unbounded"` was both
    # dead and wrong. If a schema revision introduces one, `nil` renders as an empty upper
    # bound and looks broken, which is the right kind of failure — visible.
    def occurs(particle)
      particle[:min] == particle[:max] ? particle[:min].to_s : "#{particle[:min]}–#{particle[:max]}"
    end

    # The summary buckets get their own table: they are a Hash keyed by element name, so there
    # is no attribute to put in the left column.
    def buckets_section
      rows = Ksef::FA3::Totals::ELEMENTS.map do |name|
        codes = Ksef::FA3::VatRate::BUCKETS.select { |_, pair| pair.include?(name) }.keys
        "| `#{name}` | #{codes.empty? ? "*(no rate code reaches it)*" : codes.map { |c| "`#{c}`" }.join(", ")} " \
          "| #{@schema.documentation(name) || "—"} |"
      end
      ["## Summary buckets", "",
       "`Totals#buckets` is keyed by element name. Which bucket a row lands in is decided by " \
       "its `P_12` rate code, and **the map is not invertible** — several codes share one " \
       "bucket (§8.1a). Three buckets are reachable by no rate code at all, which is a limit " \
       "of this model rather than of FA(3).", "",
       "| Element | Rate codes | Ministry's description |", "|---|---|---|", *rows, ""].join("\n")
    end

    def preamble
      version = @schema.version
      <<~HEADER
        <!-- GENERATED by `rake fa3:field_mapping` from FA(3) #{version} — DO NOT EDIT. -->

        # FA(3) field mapping

        Every field this gem's model carries, and the FA(3) element it reads and writes.

        **Generated**, not written: the attribute names come from the model classes, and the
        element names, types, cardinalities and descriptions from the pinned XSD. Editing this
        file by hand will be overwritten — change `tasks/field_mapping.rb` instead, and note
        that a declared element which does not exist in the schema fails the build rather than
        appearing here (DESIGN.md §7.2).

        Descriptions are the Ministry's own `xsd:documentation`, verbatim and in Polish, and
        are shown only where every occurrence of that element name in the schema agrees.
        **Field-name truth is the XSD**, not this table.

        This model does not carry all of FA(3). `Ksef::FA3::Invoice#unmapped_elements` reports,
        for a parsed document, exactly which element paths `#to_xml` would drop — computed by
        difference against the serializer, so it cannot go stale.

      HEADER
    end

    def footer
      <<~FOOTER
        ---

        *Schema: `#{SCHEMA}`. Regenerate with `rake fa3:field_mapping`; `rake fa3:verify`
        fails if this file is stale.*
      FOOTER
    end
  end

  def self.generate!
    File.write(OUT, Renderer.new.render, encoding: "UTF-8")
  end

  # Regenerates and reports whether the committed file was already what a fresh run produces.
  # The same gate `rake fa3:verify` applies to `generated/`, for the same reason: a generated
  # document that nobody regenerates is a hand-written one that lies (DESIGN.md §7.2).
  def self.stale?
    before = File.read(OUT, encoding: "UTF-8")
    generate!
    before != File.read(OUT, encoding: "UTF-8")
  end
end
