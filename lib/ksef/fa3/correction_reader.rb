# frozen_string_literal: true

module Ksef
  module FA3
    # Reads the correction group of `Fa`, and the summary a correction states rather than
    # derives (docs/REFERENCE.md §8.4).
    #
    # Split out of {Parser} for the same reason {RowReader} is: it is the one part of reading
    # an invoice that is entirely about corrections, and keeping it here means the parser
    # itself still reads as the shape of an invoice.
    module CorrectionReader
      class << self
        # Namespace-aware element reading; see {NodeReader}.
        include NodeReader

        # @param fa_node [Nokogiri::XML::Node] the `Fa` element
        # @return [Correction, nil] nil when the document carries no correction group
        #
        # Keyed on `DaneFaKorygowanej` rather than on `RodzajFaktury`: the whole group is
        # `minOccurs="0"`, so a `KOR` that omits it is schema-valid and simply has no
        # correction to read — and re-serialising such a document must not invent one.
        def correction_from(fa_node)
          corrected = elements(fa_node, "DaneFaKorygowanej")
          return nil if corrected.empty?

          Correction.new(
            corrected: corrected.map { |node| corrected_invoice_from(node) },
            reason: text(fa_node, "PrzyczynaKorekty"),
            effect: text(fa_node, "TypKorekty"),
            period: text(fa_node, "OkresFaKorygowanej"),
            corrected_number: text(fa_node, "NrFaKorygowany"),
            previous_seller: previous_seller_from(fa_node),
            previous_buyers: elements(fa_node, "Podmiot2K").map do |node|
              SubjectReader.subject_from(node, role: :previous_buyer)
            end
          )
        end

        # The summary the document states, read verbatim. Reached only for the types in
        # {Parser::STATED_TOTALS_TYPES}; everything else has its summaries recomputed from its
        # lines, which is what lets {RoundingInference} recover *how* they were computed.
        #
        # @return [Totals]
        def totals_from(fa_node)
          buckets = Totals::ELEMENTS.each_with_object({}) do |name, acc|
            value = text(fa_node, name)
            acc[name] = value unless value.nil?
          end

          Totals.new(buckets: buckets, gross: text!(fa_node, "P_15"))
        end

        private

        def corrected_invoice_from(node)
          CorrectedInvoice.new(
            number: text!(node, "NrFaKorygowanej"),
            issue_date: text!(node, "DataWystFaKorygowanej"),
            ksef_number: reference_from(node)
          )
        end

        # The schema's choice is mandatory: either `NrKSeF` + the number, or `NrKSeFN`. Reading
        # only the number treated "the document said neither" as "the document said NrKSeFN" —
        # and re-serialising then **asserted the corrected invoice was issued outside KSeF**,
        # a declaration nobody made, on output the XSD accepts. A document with neither is
        # schema-invalid, so it is refused here the way a missing `NrFaKorygowanej` already is.
        def reference_from(node)
          number = text(node, "NrKSeFFaKorygowanej")
          return number if number
          return nil if element(node, "NrKSeFN")

          raise ValidationError,
                "DaneFaKorygowanej for #{text(node, "NrFaKorygowanej").inspect} states neither " \
                "NrKSeFFaKorygowanej nor NrKSeFN. The schema requires one of the two, and " \
                "assuming NrKSeFN would assert the corrected invoice was issued outside KSeF."
        end

        def previous_seller_from(fa_node)
          node = element(fa_node, "Podmiot1K")
          node && SubjectReader.subject_from(node, role: :previous_seller)
        end
      end
    end
  end
end
