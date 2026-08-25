# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a's checks on {Order} and {AdvanceInvoice} — the two structures that make an
    # invoice part of an advance-payment sequence (docs/REFERENCE.md §8.5).
    #
    # Mixed into {ModelValidator}. `Zamowienie`'s positions are checked the way `FaWiersz`'s
    # are, against the same generated enum and the same `xsd:token` facets, because they are
    # the same kind of thing said about the order rather than about the sale.
    module AdvanceChecks
      # Included rather than assumed present: constant lookup is lexical.
      include FieldChecks

      private

      def advance_errors(invoice)
        [*order_errors(invoice.order), *settled_errors(invoice.advances)]
      end

      def order_errors(order)
        return [] if order.nil?
        return [Issue.new(field: "order", message: "is not a Ksef::FA3::Order")] unless order.is_a?(Order)

        order.lines.each_with_index.flat_map { |line, index| order_line_errors(line, index) }
      end

      def order_line_errors(line, index)
        field = "order.lines[#{index}]"
        return [Issue.new(field: field, message: "is not a Ksef::FA3::OrderLine")] unless line.is_a?(OrderLine)

        [
          *text_errors(line.name, "#{field}.name", LONG_TEXT),
          *text_errors(line.unit, "#{field}.unit", SHORT_TEXT),
          # `P_12Z` is optional, unlike `FaWiersz`'s `P_12` — an order position need not state
          # a rate — so nil is a value here rather than a missing one.
          line.vat_rate.nil? ? nil : enum_issue("#{field}.vat_rate", "TStawkaPodatku", line.vat_rate)
        ].compact
      end

      def settled_errors(advances)
        advances.each_with_index.flat_map do |advance, index|
          field = "advances[#{index}]"
          next [Issue.new(field: field, message: "is not a Ksef::FA3::AdvanceInvoice")] unless
            advance.is_a?(AdvanceInvoice)

          # The KSeF number's *format* is tier 2's, for the reason §8.4b gives: the only
          # pattern this gem holds comes from the OpenAPI contract, and the XSD's is wider.
          [*text_errors(advance.number, "#{field}.number", SHORT_TEXT),
           encoding_issue(advance.ksef_number, "#{field}.ksef_number")].compact
        end
      end
    end
  end
end
