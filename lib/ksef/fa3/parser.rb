# frozen_string_literal: true

require "nokogiri"

module Ksef
  module FA3
    # Reads an FA(3) document back into the model (DESIGN.md §7.6).
    #
    # ## The asymmetry with the serializer is the whole design
    #
    # {Serializer} is total: every model it is given becomes a document. The parser cannot
    # be, because FA(3) is far larger than this model. A real invoice carries `Podmiot3`,
    # `PodmiotUpowazniony`, `DaneKontaktowe`, `OkresFa`, `Zalacznik`, `Platnosc`,
    # currency-conversion twins of every tax bucket — and this models `VAT`, the correction
    # `KOR`, and the advance-payment pair `ZAL` and `ROZ`.
    #
    # So parsing takes what it understands and **keeps the whole document** on
    # {Invoice#raw_document}. Nothing is lost, but nothing is silently invented either:
    # {Invoice#unmapped_elements} names exactly what re-serialisation would drop, which a
    # caller should look at before calling `#to_xml` on a document they did not write.
    # `parse` → `to_xml` is not a safe edit-in-place operation, and that is a property of
    # the model's coverage rather than a bug to fix here.
    #
    # ## Three things it deliberately does not do
    #
    # **It does not recompute what the document states.** `P_11` is read straight into
    # {Line#net_amount} rather than being derived from `P_8B × P_9A`. The two disagree in
    # real documents — upstream's own `invoice-template-fa-3-with-custom-Subject3.xml` has a
    # row of `20 × 1000` whose net is `18000`, because a line may carry a discount — and the
    # document's own figure is the authority. Deriving it would quietly rewrite an invoice.
    #
    # **It does not validate.** A caller who wants that has `Invoice#validate!` — which runs
    # every tier that exists, 1a, 1b and 2 — and can run it on the result. Parsing a document
    # in order to inspect *why* KSeF rejected it is a normal thing to want, and a parser that
    # refuses invalid input cannot do it.
    #
    # **It does not verify the checksum of a NIP it reads.** {Subject#to_fa3} does that on
    # the way out. Reading is not the moment to reject: an invoice already in KSeF is a fact
    # whatever its NIP, and PROD is the only environment that checks the digits anyway
    # (docs/REFERENCE.md §15.3).
    module Parser
      # **All seven of `TRodzajFaktury`**, as of 2026-08-26. A spec asserts this list equals
      # the schema's enumeration, so a future revision that adds a type fails loudly here
      # rather than being refused at runtime by {#supported_type!}.
      SUPPORTED_TYPES = %w[VAT KOR ZAL ROZ UPR KOR_ZAL KOR_ROZ].freeze

      class << self
        # Namespace-aware element reading; see {NodeReader}.
        include NodeReader

        # @param xml [String, Nokogiri::XML::Document]
        # @return [Invoice] with {Invoice#raw_document} set
        # @raise [Ksef::ValidationError] if the input is not a parseable FA(3) invoice, or
        #   uses a construct this model cannot represent at all
        def parse(xml)
          document = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml)
          root = verified_root(document)
          fa_node = require_element(root, "Fa", context: Serializer::ROOT)
          # **Both before anything else is read**, because `Invoice.new`'s keyword arguments
          # evaluate in source order: anything a later argument depends on has to exist before
          # the call rather than be computed inside it.
          #
          # Reading the type inside {#build} let the row reader run first — and the Ministry's
          # collective corrections carry no `FaWiersz` at all, so a `KOR` was refused with
          # "Invoice has no FaWiersz rows". True, and the wrong diagnosis: it blamed a
          # perfectly good document for lacking something its type does not need. A ZAL is the
          # same case, its rows being `minOccurs="0"` and explicitly "opcjonalny dla faktury
          # zaliczkowej". `totals` is now the field that decides whether rows are required at
          # all, so it has to be read here too.
          #
          # The type is **collapsed before comparing**: `RodzajFaktury` is a token, so
          # `<RodzajFaktury> VAT </RodzajFaktury>` is schema-valid and means `VAT`. Compared
          # raw it was refused, with a message reading "This is a  VAT  invoice".
          type = supported_type!(Formatting.text(text(fa_node, "RodzajFaktury")) || "VAT")
          totals = Invoice::STATED_TOTALS_TYPES.include?(type) ? CorrectionReader.totals_from(fa_node) : nil

          invoice = resolve_rounding(build(document, root, fa_node, type, totals), fa_node, totals)
          # **After** the rounding inference, which decides what "derived" even means here.
          resolve_stated_gross(invoice, fa_node, totals)
        end

        private

        def verified_root(document)
          root = document.root
          if root.nil?
            detail = document.errors.first(3).map { |e| "  - #{e.message.strip}" }.join("\n")
            raise ValidationError, "Not parseable as XML:\n#{detail}"
          end

          return root if root.name == Serializer::ROOT && root.namespace&.href == Serializer::NAMESPACE

          raise ValidationError, wrong_document(root)
        end

        # An FA(2) document, or a future FA(4), reaches here: right root name, wrong
        # namespace. Naming both halves matters, because "not an FA(3) invoice" on a file
        # that plainly says `<Faktura>` is baffling without them.
        def wrong_document(root)
          "Not an FA(3) invoice: expected <#{Serializer::ROOT}> in #{Serializer::NAMESPACE}, " \
            "got <#{root.name}> in #{root.namespace&.href.inspect}"
        end

        # Built with `:per_line`, which {#resolve_rounding} then confirms or replaces. The
        # strategy is not a field in the document, so it cannot be read — only inferred from
        # the summaries, and that needs the lines parsed first.
        def build(document, root, fa_node, type, totals)
          Invoice.new(
            seller: party(root, "Podmiot1", role: :seller),
            buyer: party(root, "Podmiot2", role: :buyer),
            number: text!(fa_node, "P_2"),
            # Passed as text; {Invoice} converts it, so a malformed date surfaces as a
            # ValidationError rather than as a bare `Date::Error` from outside this gem.
            issue_date: text!(fa_node, "P_1"),
            # An invoice that states its own totals may legitimately have no rows.
            lines: RowReader.lines_from(fa_node, required: totals.nil?),
            correction: CorrectionReader.correction_from(fa_node),
            order: AdvanceReader.order_from(fa_node),
            advances: AdvanceReader.advances_from(fa_node),
            totals: totals,
            currency: text(fa_node, "KodWaluty") || "PLN",
            # Read, not defaulted. These are declarations with tax consequences — cash
            # accounting, reverse charge, split payment, an actual VAT exemption — and
            # re-emitting the defaults would silently deny every one of them
            # ({Invoice::DEFAULT_ANNOTATIONS}).
            # **`|| {}`, never the defaults.** `Adnotacje` is `minOccurs="1"`, so a document
            # without one is schema-invalid — but the parser is documented not to validate, and
            # this is representable: nothing was declared. Routing absence through
            # {Invoice::DEFAULT_ANNOTATIONS} instead emitted **eight affirmative tax
            # declarations the document never made**, invisibly, because the element paths then
            # match either way. An empty `Adnotacje` re-serialises to an empty `Adnotacje`,
            # which tier 2 reports — the invalid input yields invalid output, which is honest.
            # The defaults stay a *builder* convenience, applied only when nobody supplied any.
            annotations: ElementTree.to_hash(element(fa_node, "Adnotacje")) || {},
            invoice_type: type,
            # Kept as the string it was written as, so a round trip reproduces it byte for
            # byte — {Formatting.date_time} passes a String through untouched. Parsing it
            # into a Time would re-render it, and `+02:00` would come back as `Z`.
            issued_at: text(root, "Naglowek/DataWytworzeniaFa"),
            rounding: :per_line,
            raw_document: document
          )
        end

        def party(root, name, role:)
          SubjectReader.subject_from(require_element(root, name, context: Serializer::ROOT), role: role)
        end

        # {Invoice} models the types in {SUPPORTED_TYPES} (DESIGN.md §7.4). Accepting an
        # unmodelled type produces something far worse than a refusal, and `KOR` is the case
        # that showed it:
        # before 2026-08-24 one parsed and re-serialised kept its `RodzajFaktury` and `P_2` —
        # and therefore KSeF's whole duplicate key (docs/REFERENCE.md §15.2) — while dropping
        # `DaneFaKorygowanej` and recomputing the summaries from rows whose `StanPrzed` marker
        # was ignored. A -9.84 correction came back as a +34.44 invoice, XSD-valid and
        # plausible. The same is true of every type still on the list.
        def supported_type!(type)
          return type if SUPPORTED_TYPES.include?(type)

          raise ValidationError,
                "This is a #{type} invoice, and only #{SUPPORTED_TYPES.join(", ")} are modelled " \
                "so far (DESIGN.md §7.4). The document itself is fine — but parsing it would " \
                "drop the fields that make it a #{type}, and re-serialising the result would " \
                "produce a different invoice under the same number."
        end

        # Delegated to {RoundingInference}: the strategy is not in the document, so it has
        # to be inferred from the summaries — which is reasoning about arithmetic rather
        # than reading elements, and belongs somewhere else.
        #
        # Skipped entirely when the invoice states its own totals. There is then nothing to
        # infer: the summaries were read, not computed, so no strategy produced them and
        # comparing the lines against them would answer a question nobody asked.
        def resolve_rounding(invoice, fa_node, totals)
          return invoice if totals

          RoundingInference.apply(
            invoice, RoundingInference.stated_from(fa_node) { |node, name| text(node, name) }
          )
        end

        # `P_15` is `minOccurs="1"`, so every document states one — but an invoice that
        # derives its summary recomputes it from buckets that are individually rounded, and
        # the two need not agree. {Invoice#stated_gross} carries the document's figure **only
        # when it differs**, which is the same rule {Line#row_number} follows and for the same
        # reason: stored unconditionally it would make a built invoice unequal to itself
        # parsed back, and DESIGN.md §7.6's round-trip law with it.
        #
        # One sample in twenty-six needs it. Przykład 1 states `2051` where the buckets sum to
        # `2050.99`; re-emitting the derived figure made the Ministry's own first example a
        # grosz cheaper, invisibly (docs/REFERENCE.md §17.1).
        def resolve_stated_gross(invoice, fa_node, totals)
          return invoice if totals

          stated = text(fa_node, "P_15")
          return invoice if stated.nil?

          gross = Formatting.decimal(stated).round(Formatting::AMOUNT_SCALE)
          gross == invoice.gross_total ? invoice : invoice.with(stated_gross: gross)
        end
      end
    end
  end
end
