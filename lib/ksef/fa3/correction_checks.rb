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
      # nothing left to check about a real one — only that it *is* one. Without this a
      # `totals:` of the wrong class reached {DocumentMapping} and raised `NoMethodError`,
      # which is outside this gem's hierarchy and so outside {Invoice#errors}' rescue.
      def totals_errors(totals)
        return [] if totals.nil? || totals.respond_to?(:to_fa3)

        [Issue.new(field: "totals", message: "is not a Ksef::FA3::Totals")]
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
        unless correction.respond_to?(:corrected)
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
            entry.respond_to?(:ksef_number)

          [*text_errors(entry.number, "#{field}.number", SHORT_TEXT, required: true),
           ksef_number_issue(entry.ksef_number, "#{field}.ksef_number")].compact
        end
      end

      # Shape only, and **no checksum**. `Ksef::KsefNumber.parse` would verify the CRC-8 of
      # §13 — and all six KSeF numbers in the Ministry's own worked corrections fail it
      # (measured 2026-08-24, docs/REFERENCE.md §8.4a). They are illustrative placeholders,
      # not numbers KSeF ever issued, and nothing upstream says KSeF checks the checksum of
      # a *referenced* number. Rejecting on it would be tier 1 refusing the Ministry's own
      # documents, which is precisely the failure the whitespace-collapse bug was.
      def ksef_number_issue(value, field)
        return nil if value.nil? || KsefNumber::FORMAT.match?(value.to_s)

        Issue.new(field: field,
                  message: "#{value.inspect} is not shaped like a KSeF number " \
                           "(NIP-YYYYMMDD-technical-checksum, docs/REFERENCE.md §13)")
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
