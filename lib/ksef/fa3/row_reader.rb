# frozen_string_literal: true

module Ksef
  module FA3
    # Reads the `FaWiersz` rows of an invoice into {Line} objects.
    #
    # Split out of {Parser} because a row is where FA(3)'s optionality is at its most
    # aggressive: every child of `TFaWiersz` except `NrWierszaFa` is `minOccurs="0"`, so most
    # of what this does is decide which absences the model can absorb and which it cannot.
    module RowReader
      class << self
        # Namespace-aware element reading; see {NodeReader}.
        include NodeReader

        def lines_from(fa_node)
          rows = elements(fa_node, "FaWiersz")
          raise ValidationError, "Invoice has no FaWiersz rows" if rows.empty?

          rows.map { |row| line_from(row) }
        end

        private

        def line_from(row)
          net_amount = text(row, "P_11")
          quantity = text(row, "P_8B")
          unit_price = text(row, "P_9A")

          if net_amount.nil? && (quantity.nil? || unit_price.nil?)
            raise ValidationError,
                  "FaWiersz #{text(row, "NrWierszaFa") || "(unnumbered)"} has neither P_11 " \
                  "nor both of P_8B and P_9A, so its net value cannot be established"
          end

          # Passed as the strings they were written as; {Line} converts them, so decimal
          # coercion lives in one place rather than being repeated per caller.
          #
          # `P_7` is `minOccurs="0"` ("optional for art. 106j ust. 3 pkt 2" — corrections), so
          # it is read leniently and omitted again on the way out. `P_12` is optional too, but
          # unlike a name it is not something this model can do without: every summary bucket
          # is chosen by rate code, so a row without one cannot be re-serialised at all. Hence
          # a refusal that says so, rather than one implying the document is malformed.
          Line.new(
            name: text(row, "P_7"), unit: text(row, "P_8A"),
            quantity: quantity, net_unit_price: unit_price,
            vat_rate: rate_for(row), net_amount: net_amount
          )
        end

        def rate_for(row)
          rate = text(row, "P_12")
          return rate if rate

          raise ValidationError,
                "FaWiersz #{text(row, "NrWierszaFa") || "(unnumbered)"} states no P_12 rate code. " \
                "The document may be valid — P_12 is optional for the simplified and margin " \
                "invoices of art. 106e ust. 2-3 — but this model derives every tax summary " \
                "from the rate, so it cannot represent the row (DESIGN.md §7.4)."
        end
      end
    end
  end
end
