# frozen_string_literal: true

module Ksef
  module FA3
    # A complete FA(3) invoice.
    #
    # Covers **all seven** of `TRodzajFaktury` (DESIGN.md §7.4), which differ from the common
    # core in four optional fields and one relaxation.
    #
    # A correction carries a {Correction} saying what it corrects — `KOR`, `KOR_ZAL`, `KOR_ROZ`
    # (§8.4). An advance invoice carries an {Order} and a settlement invoice the
    # {AdvanceInvoice}s it settles — `ZAL`, `ROZ`, and their corrections (§8.5). Every type but
    # `VAT` may state its {Totals} rather than have them derived, and because it may, it may
    # have no lines at all — or lines that name goods and state no amount, which is what a
    # simplified `UPR` invoice is (§8.6).
    Invoice = Data.define(
      :seller, :buyer, :number, :issue_date, :lines,
      :currency, :issued_at, :rounding, :invoice_type, :annotations,
      :correction, :totals, :order, :advances, :raw_document, :stated_gross
    )

    # Computation, defaults and serialisation for {Ksef::FA3::Invoice}.
    class Invoice
      # Both strategies are permitted by Polish VAT law, and silently choosing one creates
      # one-grosz mismatches against a user's ERP (DESIGN.md §7.3).
      ROUNDING_STRATEGIES = %i[per_line per_summary].freeze

      # The **default** annotations: all five flags plus the three wrapper elements are
      # mandatory (§8.2), and every one of them is the same on an ordinary domestic invoice.
      # Defaulting them to "not applicable" is what makes such an invoice possible without
      # the caller knowing any of this.
      #
      # They are a *default*, not a constant of the format. Until 2026-08-24 they were emitted
      # unconditionally, which meant parsing an invoice that declared cash accounting
      # (`P_16`), reverse charge (`P_18`), split payment (`P_18A`) or an actual VAT exemption
      # (`Zwolnienie/P_19`) and re-serialising it **silently reset every one of them to "does
      # not apply"** — and, for the exemption, wrote a positive `P_19N` asserting that none
      # applied. Because the element paths are identical either way,
      # {Provenance#unmapped_elements} could not see it. These are declarations with tax
      # consequences; {Parser} now reads them and {#annotations} carries them.
      DEFAULT_ANNOTATIONS = {
        "P_16" => Formatting.flag(false),
        "P_17" => Formatting.flag(false),
        "P_18" => Formatting.flag(false),
        "P_18A" => Formatting.flag(false),
        "Zwolnienie" => { "P_19N" => "1" },
        "NoweSrodkiTransportu" => { "P_22N" => "1" },
        "P_23" => Formatting.flag(false),
        "PMarzy" => { "P_PMarzyN" => "1" }
      }.freeze

      # The invoice kinds whose tax summary **may** be stated rather than derived from the
      # rows. Lives here rather than on {Parser} because both halves need it: the parser reads
      # a stated summary for these types, and {ModelValidator} reports one set on any other —
      # where it would be emitted verbatim, never read back, and disagree with the lines with
      # nothing to notice (docs/REFERENCE.md §8.4).
      #
      # **"May", not "always".** Across the `ZAL`/`ROZ` family the stated buckets never equal
      # the row totals (§8.5's table): a `ZAL` has no rows, and a `ROZ` states what remains
      # *after* the advance, which this document does not contain enough to compute. A `KOR` is
      # more varied — Przykład 3's single delta row reproduces its buckets exactly. That is why
      # {SummaryChecks} keys the *requirement* to what a document carries rather than to its
      # type; making it type-based would reject that worked example.
      STATED_TOTALS_TYPES = %w[KOR ZAL ROZ UPR KOR_ZAL KOR_ROZ].freeze

      NEEDS_LINES = "An invoice needs at least one line, unless it states its own totals. " \
                    "A collective correction may have no FaWiersz at all — see " \
                    "Ksef::FA3::Totals and docs/REFERENCE.md §8.4."

      # Everything except {#raw_document}: the fields that make this invoice *this* invoice.
      # {Provenance} reads this to decide what equality, hashing and `#inspect` cover.
      IDENTITY = (members - [:raw_document]).freeze

      # Equality, `#inspect` and {Provenance#unmapped_elements} — everything to do with the
      # document this invoice may have been read from.
      include Provenance
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical
      # `#to_fa3` and the element-name mapping behind it.
      include DocumentMapping

      # The summary arithmetic (§8.1a), extracted so this class stays under its length gate
      # and so tier 3 has one obvious place to read the figures from.
      include Summaries

      # `issued_at` is normalised to the string the document will carry, which is the same
      # rule {Address} and {Line} follow: **the model stores the document's representation,
      # not the caller's input.** A `Time` renders to `"2026-08-22T10:00:00Z"` here rather
      # than at serialisation, so an invoice built from a Time and the same invoice parsed
      # back from XML are one object — the round-trip law of DESIGN.md §7.6 would otherwise
      # fail on a field whose value never actually changed.
      #
      # `nil` is left alone, and means something different: not "no timestamp" but "stamp it
      # when you serialise". Such an invoice is not fully determined and cannot round-trip
      # to an equal object, which is a property of that choice rather than a defect.
      #
      # `lines` may be empty **only** when the invoice states its own `totals`. `FaWiersz` is
      # `minOccurs="0"`, and a collective correction legitimately has no rows — but without
      # rows *and* without stated totals there is nothing to compute a summary from, and the
      # result would be a document declaring zero tax on an invoice that means to declare
      # some.
      def initialize(seller:, buyer:, number:, issue_date:, lines: [],
                     currency: "PLN", issued_at: nil, rounding: :per_line, invoice_type: "VAT",
                     annotations: nil, correction: nil, totals: nil, order: nil, advances: [],
                     raw_document: nil, stated_gross: nil)
        rows = self.class.rows_for(lines, rounding: rounding, totals: totals)

        super(
          seller: seller, buyer: buyer, lines: rows, rounding: rounding,
          number: Formatting.text(number),
          currency: Formatting.text(currency),
          invoice_type: Formatting.text(invoice_type),
          correction: correction, totals: totals, order: order,
          advances: Correction.wrap(advances).dup.freeze, raw_document: raw_document,
          stated_gross: self.class.scaled_gross(stated_gross, totals, rows, rounding),
          # `issue_date` is canonicalised for the same reason `issued_at` is: a String and the
          # Date it denotes must not produce two unequal invoices (§8.2b).
          issue_date: Formatting.to_date(issue_date),
          issued_at: issued_at.nil? ? nil : Formatting.date_time(issued_at),
          # Defaulted here rather than at serialisation, so a built invoice and the same
          # invoice parsed back hold the same value and compare equal.
          annotations: annotations || DEFAULT_ANNOTATIONS
        )
      end

      # `P_15` as the **document stated it**, for an invoice whose summary is otherwise derived
      # from its rows. `nil` for a built invoice with nothing to state, `nil` when {#totals} is
      # present (a stated summary already carries its own gross), and **`nil` when it equals
      # what the rows derive** — the {Line#row_number} rule, and here for the same reason:
      # kept unconditionally, a built invoice would be unequal to itself parsed back and
      # DESIGN.md §7.6 would fail.
      #
      # That canonicalisation lives here rather than in the parser deliberately. It was in the
      # parser until the 2026-08-26 audit, which pointed out that {.positioned} does the
      # equivalent job for `row_number` in the **model**, so `Invoice.new(stated_gross:)` and
      # `#with(stated_gross:)` — both public — bypassed it and broke the round-trip law with
      # no diagnostic.
      #
      # Why the field exists at all: `P_15` is mandatory in `Fa`, so **every** document states
      # it, and a derived gross need not equal the stated one. The Ministry's Przykład 1 is the
      # witness — its nets are computed back from round gross prices of 2000/50/1 and rounded
      # down, so the rows total 2050.99 against a stated `P_15` of 2051. Deriving it re-emitted
      # the invoice a grosz cheaper, with `#unmapped_elements` silent (the element is present
      # either way) and `#errors` empty. A stated amount altered in silence — the same class as
      # `P_9A` (§8.6), and found the same way, by measuring rather than by reading the code.
      def self.scaled_gross(stated_gross, totals, rows, rounding)
        return nil if stated_gross.nil? || totals

        gross = Formatting.decimal(stated_gross).round(Formatting::AMOUNT_SCALE)
        gross == Summaries.derived_gross(rows, rounding) ? nil : gross
      end

      # The two constructor invariants that are about the line list rather than a field, kept
      # together because both have to hold before anything is stored.
      def self.rows_for(lines, rounding:, totals:)
        unless ROUNDING_STRATEGIES.include?(rounding)
          raise ValidationError,
                "Unknown rounding strategy #{rounding.inspect}; expected one of #{ROUNDING_STRATEGIES.inspect}"
        end

        rows = positioned(lines.nil? ? [] : lines)
        raise ValidationError, NEEDS_LINES if rows.empty? && totals.nil?

        rows.freeze
      end

      # `Line#row_number` means "this row's number is *not* its position" — nil says "number
      # me by position". Only the invoice knows a line's position, so only the invoice can
      # canonicalise: a caller who states `row_number: 1` on the first line describes exactly
      # the document a caller who states nothing does, and leaving the two unequal broke
      # DESIGN.md §7.6's round-trip law for an ERP that always supplies row numbers.
      #
      # `each_with_index.map` returns a new array, so a caller's own is never modified — and
      # that copy is what {.rows_for} freezes, `lines` being an invariant of the object rather
      # than a view onto theirs.
      def self.positioned(lines)
        lines.each_with_index.map do |line, index|
          next line unless line.is_a?(Line) && line.row_number == index + 1

          line.with(row_number: nil)
        end
      end

      # Net totals per rate code, in the order the lines first mention each rate, so the
      def to_xml = Serializer.new(to_fa3).to_xml

      # Every validation tier that exists, model first (DESIGN.md §7.7). Document and schema
      # checks then run on the same bytes; their relative order is not fixed by §7.7 and does
      # not matter, since neither can affect the other's input.
      #
      # **Tier 1a first, and nothing else runs if it fails.** {ModelValidator}'s contract is
      # that a model it passes can be serialized; a model it rejects generally cannot, because
      # serialisation *raises* on a bad NIP, a nameless seller or a rate code with no summary
      # bucket. Attempting `#to_xml` anyway would replace a list of addressed errors with a
      # single exception about whichever one came first. ("A line with no derivable net" was
      # on that list until 2026-08-26, when such a row became legal — {Line#net} answers nil
      # and the row serialises without a `P_11`. The short-circuit's justification survives on
      # the remaining three; the guard against that row is now tier 1's alone.)
      #
      # Then {DocumentValidator} (tier 1b) and {Validator} (tier 2) on the same bytes.
      #
      # **Tier 3 is deliberately not here.** {BusinessValidator} reconciles figures the
      # document states independently, and a Polish invoice priced from round gross prices
      # routinely fails that check while being perfectly legal — so making it an error would
      # refuse legal documents, which is exactly what got KSeF's own proposed business rule
      # withdrawn (docs/REFERENCE.md §15.6). It is advisory, and lives on {#warnings}.
      #
      # @param max_bytes [Integer] the document-size ceiling for this context. KSeF's 1 MB is a
      #   *default* that an organisation can have raised on application (docs/REFERENCE.md
      #   §15.5); pass the value `GET /limits/context` reports if yours differs.
      # @return [Array<Issue>] empty when the invoice is sound
      def errors(max_bytes: DocumentValidator::MAX_BYTES)
        model = ModelValidator.errors_for(self)
        return model unless model.empty?

        document = to_xml
        DocumentValidator.errors_for(document, max_bytes: max_bytes) +
          Validator.errors_for(document).map { |message| Issue.new(field: "schema", message: message) }
      rescue Ksef::Error => e
        # A serialisation refusal the model tier did not anticipate. Reported rather than
        # raised, so `#errors` always answers the question it was asked.
        [Issue.new(field: "document", message: e.message)]
      end

      # Tier 3 (§7.7): reconciliation between figures the document states independently.
      # **Advisory** — these never make an invoice invalid and never block a send. A warning
      # here means "these numbers do not add up; that may be fine", not "KSeF will reject
      # this" (docs/REFERENCE.md §17.1, and §14.3 for the precedent).
      #
      # @return [Array<Issue>] empty when nothing disagrees, or when nothing states two
      #   figures independently to compare
      def warnings = BusinessValidator.warnings_for(self)

      def valid?(**) = errors(**).empty?

      # @raise [Ksef::ValidationError] listing every problem found, not merely the first
      def validate!(**)
        found = errors(**)
        return true if found.empty?

        raise ValidationError,
              "Invoice #{number.inspect} is not valid:\n#{found.sort.map { |issue| "  - #{issue}" }.join("\n")}"
      end
    end
  end
end
