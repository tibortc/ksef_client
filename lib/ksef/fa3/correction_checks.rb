# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a's checks on {Correction}, {CorrectedInvoice} and {Totals} (docs/REFERENCE.md
    # §8.4).
    #
    # Split out of {ModelValidator} for length, and because a correction is a self-contained
    # subject: it has its own value objects, its own optionality — `TypKorekty` is
    # `minOccurs="0"`, so nil is a value and not an omission — and the one cross-field rule
    # tier 1 carries.
    #
    # Mixed into {ModelValidator}, and brings {SubjectChecks} with it: `Podmiot1K` and
    # `Podmiot2K` are parties like any other.
    module CorrectionChecks
      # Included rather than assumed present. Constant lookup is **lexical**, so `SHORT_TEXT`
      # here resolves through this module's own ancestors and not through whatever
      # {ModelValidator} happens to have mixed in.
      include FieldChecks
      include SubjectChecks

      private

      # {Totals} validates its own bucket names and coerces its own amounts, so there is
      # nothing left to check about a real one — only that it *is* one, and that the invoice
      # is a kind that states its summary at all.
      #
      # **`is_a?`, not `respond_to?(:to_fa3)`.** Duck-typing here re-opened the hole this
      # check was added to close: a `Line` or a `Subject` also answers `to_fa3`, so one passed
      # the model tier and then made `#to_xml` raise `ArgumentError: missing keyword` — outside
      # this gem's hierarchy and so outside {Invoice#errors}' rescue. The message already
      # promises a class; now it checks one.
      def totals_errors(invoice)
        totals = invoice.totals
        return [] if totals.nil?
        return [Issue.new(field: "totals", message: "is not a Ksef::FA3::Totals")] unless totals.is_a?(Totals)
        return [] if Invoice::STATED_TOTALS_TYPES.include?(invoice.invoice_type)

        [Issue.new(field: "totals",
                   message: "is set on a #{invoice.invoice_type} invoice, whose summary this " \
                            "model computes from its lines. A stated summary is emitted " \
                            "verbatim and never read back, so the document would disagree " \
                            "with its own rows (docs/REFERENCE.md §8.4)")]
      end

      # **The other half of "a correction's summaries are read, never computed"** — the half
      # that was missing until an audit on 2026-08-24 found it, three lenses independently.
      #
      # docs/REFERENCE.md §8.4 states the rule, and {Parser} kept it: every `KOR` it reads gets
      # a {Totals}. But {DocumentMapping#summary} falls back to the line-derived buckets
      # whenever `totals` is nil, and nothing required a *built* correction to state any. A
      # `StanPrzed` row is the position **as it was before the correction** — it was already
      # invoiced on the original document — so summing it into the delta buckets counts it
      # twice, with the wrong sign. The Ministry's own Przykład 2, built without `f.totals`,
      # declared `P_15 = 3799.98` where the correction it describes is `-200.00`: a refund
      # turned into a charge, XSD-valid, tier 1 silent and `unmapped_elements` empty.
      #
      # Scoped to `state_before` rather than to the type: a correction whose rows already
      # *are* the deltas computes correctly, and the Ministry's Przykład 3 is exactly that
      # shape. Refusing every derived correction would reject it.
      def before_state_errors(invoice)
        return [] unless invoice.totals.nil?
        return [] unless invoice.lines.any? { |line| line.is_a?(Line) && line.state_before }

        [Issue.new(field: "totals",
                   message: "is required when a line is marked state_before. Such a row shows " \
                            "the position as it was before the correction, so deriving the " \
                            "summary from the rows counts it as a sale — state the delta " \
                            "instead (docs/REFERENCE.md §8.4)")]
      end

      # The one cross-field rule here, and it is a field *definition* rather than a business
      # rule: `PrzyczynaKorekty` is documented as *"przyczyna korekty dla faktur
      # korygujących"*, so the correction group belongs to a correcting type. The XSD cannot
      # express that — the group sits in the same sequence whatever `RodzajFaktury` says —
      # which is exactly why tier 1 is the place for it.
      #
      # The converse is deliberately **not** checked: the group is `minOccurs="0"`, so a
      # `KOR` without one is schema-valid, and refusing it would be inventing a rule
      # (docs/REFERENCE.md §8.4).
      def correcting_type_errors(invoice)
        return [] if invoice.correction.nil? || Correction::CORRECTING_TYPES.include?(invoice.invoice_type)

        [Issue.new(field: "correction",
                   message: "is set on a #{invoice.invoice_type} invoice; the correction elements " \
                            "belong to #{Correction::CORRECTING_TYPES.join(", ")}")]
      end

      # `PrzyczynaKorekty`, `OkresFaKorygowanej` and `NrFaKorygowany` are all `TZnakowy`.
      # `TypKorekty` is optional — `minOccurs="0"` — so nil is not an error, which is why it
      # cannot simply go through {FieldChecks#enum_issue}.
      def correction_errors(correction)
        return [] if correction.nil?
        unless correction.is_a?(Correction)
          return [Issue.new(field: "correction", message: "is not a Ksef::FA3::Correction")]
        end

        [
          *correction_text_errors(correction),
          *corrected_errors(correction.corrected),
          *previous_party_errors(correction)
        ]
      end

      def correction_text_errors(correction)
        [
          *text_errors(correction.reason, "correction.reason", SHORT_TEXT),
          *text_errors(correction.period, "correction.period", SHORT_TEXT),
          *text_errors(correction.corrected_number, "correction.corrected_number", SHORT_TEXT),
          correction.effect.nil? ? nil : enum_issue("correction.effect", "TTypKorekty", correction.effect)
        ].compact
      end

      def corrected_errors(corrected)
        corrected.each_with_index.flat_map do |entry, index|
          field = "correction.corrected[#{index}]"
          next [Issue.new(field: field, message: "is not a Ksef::FA3::CorrectedInvoice")] unless
            entry.is_a?(CorrectedInvoice)

          [*text_errors(entry.number, "#{field}.number", SHORT_TEXT, required: true),
           ksef_number_issue(entry.ksef_number, "#{field}.ksef_number")].compact
        end
      end

      # **Encoding only. Neither the checksum nor the format is tier 1's to judge**, and each
      # omission has its own reason (docs/REFERENCE.md §8.4a, §8.4b).
      #
      # The checksum, because all six KSeF numbers in the Ministry's own worked corrections
      # fail §13's CRC-8 — they are well-formed placeholders, our CRC is right, and checking
      # it would make tier 1 refuse the Ministry's documents.
      #
      # The format, because the only pattern this gem holds is `KsefNumber::FORMAT`, taken
      # from the **OpenAPI contract**, which admits the NIP issuer form alone. The FA(3)
      # **XSD** additionally admits `M\d{9}` and `[A-Z]{3}\d{7}`. The two pinned artifacts
      # genuinely differ, and each is right about its own domain: the contract governs what a
      # lookup URL may contain, the XSD what a *document* may reference. Judging a document
      # field by the contract's pattern flagged an XSD-valid `M…` number as malformed. Tier 2
      # owns the format here, and it reports it against the element.
      def ksef_number_issue(value, field)
        encoding_issue(value, field)
      end

      def previous_party_errors(correction)
        seller = correction.previous_seller
        [
          *(seller && subject_errors(seller, "correction.previous_seller", role: :previous_seller)),
          *correction.previous_buyers.each_with_index.flat_map do |subject, index|
            subject_errors(subject, "correction.previous_buyers[#{index}]", role: :previous_buyer)
          end
        ]
      end
    end
  end
end
