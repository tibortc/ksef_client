# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a's checks on {Correction} and {CorrectedInvoice} (docs/REFERENCE.md §8.4).
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

      # The one cross-field rule here, and it is a field *definition* rather than a business
      # rule: the XSD's own annotation on the sequence that holds these elements reads *"Dane
      # dla przypadków, gdy pole RodzajFaktury przyjmuje wartości KOR, KOR_ZAL lub KOR_ROZ"*.
      # What the schema cannot do is enforce it — the group sits in the same sequence whatever
      # the type, so a `VAT` invoice carrying `DaneFaKorygowanej` validates clean. That gap is
      # exactly why tier 1 is the place for it.
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
