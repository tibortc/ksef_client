# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a — checks on the invoice **object**, before it becomes a document
    # (DESIGN.md §7.7, as amended 2026-08-24).
    #
    # Fast, field-addressed, and needing no XML: required fields, enum membership, NIP
    # checksums, string lengths, date sanity. The point is not to duplicate the schema — tier
    # 2 does that better — but to say *which value* is wrong in terms the caller recognises,
    # before they have to read a libxml2 message about a facet.
    #
    # ## It also has a contract tier 2 cannot give
    #
    # **If this passes, `#to_xml` will not raise.** Serialisation refuses several things
    # outright — a NIP that fails its checksum, a seller with no name or address, a rate code
    # with no summary bucket — and each arrives as an exception rather than a message. A line
    # whose net can be neither read nor derived was on that list until 2026-08-26; it is now a
    # legal row that serialises without a `P_11`, and the objection to it is {NO_AMOUNT}, which
    # this tier raises on its own account rather than on the
    # serializer's behalf. Checking them here turns every one into a
    # collected, addressed error, which is why {Invoice#errors} runs this first and stops if
    # anything comes back.
    #
    # ## What it deliberately does not check
    #
    # **Arithmetic.** Whether the summaries reconcile with the lines is tier 3
    # (docs/REFERENCE.md §15.6), and it is not built.
    #
    # **Anything global.** Duplicate detection (§15.2) is a property of KSeF's ten-year
    # history, not of this document.
    #
    # **Sign.** `TKwotowy` permits negative amounts and corrections need them, so a negative
    # net is not an error here.
    #
    # ## Where the checks live
    #
    # This module decides *what an invoice has* — a seller, a buyer, a header, annotations,
    # lines — and the checks for each subject live with that subject: {SubjectChecks} for the
    # four `Podmiot` roles, {CorrectionChecks} for the correction group, {SummaryChecks} for
    # the stated tax summary, {AdvanceChecks} for `Zamowienie` and `FakturaZaliczkowa`, and
    # {FieldChecks} for anything measured against an `xsd:token` facet. All five are mixed in
    # here, so they share one `self` and can call each other.
    module ModelValidator
      # `Adnotacje` is an anonymous complex type, so the generated metadata keys it by path
      # rather than by name — the same key {Serializer} resolves when it rejects an unknown
      # element there.
      ANNOTATIONS_TYPE = "Faktura/Fa/Adnotacje"

      # §15.4: `P_1` must not be later than the date KSeF accepts the document — a date in
      # *KSeF's* timezone, which is unknowable here. Comparing against a local `Date.today`
      # would reject perfectly good invoices around midnight for any caller west of Warsaw, so
      # this allows a day of slack and flags only a date that is unambiguously in the future.
      # The same-day boundary is left to the service, which is the only party that can decide
      # it.
      FUTURE_TOLERANCE_DAYS = 1

      NO_RATE = "states an amount but no P_12 rate code, so there is no bucket to put it in. " \
                "This invoice derives its summary from its rows, so the amount would simply be " \
                "missing from the tax base (docs/REFERENCE.md §8.6)."

      NO_AMOUNT = "states no amount, and this invoice derives its summary from its rows, so it " \
                  "would contribute nothing to the tax base. Either give the row an amount, or " \
                  "state the invoice's summary directly (docs/REFERENCE.md §8.6)."

      class << self
        # Value-level checks: encoding, xsd:token collapse, lengths, enum membership.
        include FieldChecks
        # The party checks, which all four `Podmiot` roles share.
        include SubjectChecks
        # The correction group and its value objects. It includes {SubjectChecks} itself,
        # `Podmiot1K` and `Podmiot2K` being parties like any other.
        include CorrectionChecks
        # The stated tax summary, which spans corrections and the advance-payment types alike.
        include SummaryChecks
        # `Zamowienie` and `FakturaZaliczkowa`, for `ZAL` and `ROZ`.
        include AdvanceChecks

        # @param invoice [Invoice]
        # @return [Array<Issue>] empty when the model is sound
        def errors_for(invoice)
          [
            *subject_errors(invoice.seller, "seller", role: :seller),
            *subject_errors(invoice.buyer, "buyer", role: :buyer),
            *header_errors(invoice),
            *annotation_errors(invoice.annotations),
            *summary_errors(invoice),
            *type_specific_errors(invoice),
            *invoice.lines.each_with_index.flat_map do |line, index|
              line_errors(line, index, derived: invoice.totals.nil?)
            end
          ]
        end

        private

        # The stated tax summary, from both directions: set where it does not belong, and
        # absent where the rows cannot stand in for it ({SummaryChecks}).
        def summary_errors(invoice)
          [*totals_errors(invoice), *derived_summary_errors(invoice)]
        end

        # What each family of invoice types adds to the common core: the correction group
        # ({CorrectionChecks}) and the advance-payment structures ({AdvanceChecks}).
        def type_specific_errors(invoice)
          [*advance_errors(invoice), *correction_errors(invoice.correction),
           *correcting_type_errors(invoice)]
        end

        def header_errors(invoice)
          issues = []
          issues.concat(text_errors(invoice.number, "number", SHORT_TEXT, required: true))
          issues << enum_issue("currency", "TKodWaluty", invoice.currency)
          issues << enum_issue("invoice_type", "TRodzajFaktury", invoice.invoice_type)
          issues << future_date_issue(invoice.issue_date)
          issues.compact
        end

        # `annotations` is a public constructor field the model tier used to ignore entirely, so
        # an unknown key passed the model and then made the serializer raise — the one hole in
        # this module's contract that a 2026-08-24 review could still find.
        #
        # **It recurses**, because the serializer does. Checking one level deep left
        # `Zwolnienie => { "P_19X" => "1" }` passing the model and raising on the way out; the
        # nested type is resolved through {Serializer.child_type_key}, the same call the
        # serializer makes, so the two agree about what belongs where — including that a leaf
        # takes no children at all, which is the case the first recursion missed.
        def annotation_errors(annotations, type_key = ANNOTATIONS_TYPE, field = "annotations")
          return [Issue.new(field: field, message: "must be a Hash")] unless annotations.is_a?(Hash)

          # **A leaf first.** An element takes text when the metadata gives it no content model
          # — either no entry at all, or an entry whose `:content` is nil because the type is
          # `simpleContent`. A Hash under one is something the serializer refuses outright.
          # Falling through to the guard below treated a leaf's empty element list as "the
          # codegen changed" and returned no issues, so `annotations: {"P_16" => {"X" => 1}}`
          # passed tier 1a and then made `#to_xml` raise: the contract above, broken by the
          # recursion added to uphold it (found by audit 2026-08-26).
          #
          # The test was `Types[type_key].nil?`, which was equivalent until the codegen started
          # emitting simpleContent types — `TNaglowek/KodFormularza` is the first entry that
          # exists *and* is textual. Asking about `:content` is the exact question.
          if Generated::Types[type_key].nil? || Generated::Types[type_key][:content].nil?
            return [Issue.new(field: field, message: "takes a text value, not nested elements")]
          end

          known = Generated::Types.ordered_elements(type_key)
          # A *known* type with no elements means the generated metadata no longer describes it
          # as this code expects — a codegen change, not a caller's mistake.
          return [] if known.empty?

          named = annotations.transform_keys(&:to_s)
          unknown_annotations(named, known, type_key, field) + nested_annotation_errors(named, known, type_key, field)
        end

        def unknown_annotations(named, known, type_key, field)
          (named.keys - known.map { |particle| particle[:name] }).map do |unknown|
            Issue.new(field: field,
                      message: "#{unknown.inspect} is not an element of #{type_key.split("/").last}")
          end
        end

        def nested_annotation_errors(named, known, type_key, field)
          known.flat_map do |particle|
            value = named[particle[:name]]
            next [] unless value.is_a?(Hash)

            annotation_errors(value, Serializer.child_type_key(type_key, particle),
                              "#{field}.#{particle[:name]}")
          end
        end

        # @param derived [Boolean] whether this invoice computes its summary from its rows.
        #   When it does, every row has to be placeable in a bucket; when it states its summary
        #   instead, a row may name goods and no amount at all (docs/REFERENCE.md §8.6).
        def line_errors(line, index, derived:)
          field = "lines[#{index}]"
          return [Issue.new(field: field, message: "is not a Ksef::FA3::Line")] unless line.is_a?(Line)

          [
            *text_errors(line.name, "#{field}.name", LONG_TEXT),
            *text_errors(line.unit, "#{field}.unit", SHORT_TEXT),
            # `P_12` is `minOccurs="0"`, so nil is a value rather than an omission — what it
            # costs is checked below, and only where it costs anything.
            line.vat_rate.nil? ? nil : enum_issue("#{field}.vat_rate", "TStawkaPodatku", line.vat_rate),
            derived ? unsummarised_issue(line, field) : nil
          ].compact
        end

        # A row that cannot be placed in a summary bucket, on an invoice whose summary is built
        # by adding the rows up. Either way the row's amount is absent from the tax base, and
        # neither the XSD nor `#unmapped_elements` can see that — the second is blind to values
        # and the first to arithmetic.
        # The two halves are addressed differently on purpose. `NO_RATE` has one remedy and
        # one field — supply `P_12` — so it points at it. `NO_AMOUNT` does not: the row could
        # gain `P_11`, or a quantity and a unit price, or the invoice could state its summary
        # instead, so the honest address is the row.
        def unsummarised_issue(line, field)
          return nil if line.summarised?

          return Issue.new(field: "#{field}.vat_rate", message: NO_RATE) if line.priced?

          Issue.new(field: field, message: NO_AMOUNT)
        end

        def future_date_issue(issue_date)
          latest = Date.today + FUTURE_TOLERANCE_DAYS
          return nil unless issue_date > latest

          Issue.new(field: "issue_date",
                    message: "#{issue_date} is in the future; KSeF rejects an issue date later " \
                             "than the date it accepts the document (docs/REFERENCE.md §15.4)")
        end
      end
    end
  end
end
