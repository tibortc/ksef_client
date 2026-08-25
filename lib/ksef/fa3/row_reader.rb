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

        # @param fa_node [Nokogiri::XML::Node] the `Fa` element
        # @param required [Boolean] whether an invoice with no rows is an error. False for a
        #   correction that states its own totals: `FaWiersz` is `minOccurs="0"` and the
        #   Ministry's own collective corrections carry none (docs/REFERENCE.md §8.4).
        # The row number is read as stated; {Invoice.positioned} is what reduces it to nil
        # when it merely repeats the position. One place decides, and it is the one that knows
        # what a line's position is.
        def lines_from(fa_node, required: true)
          rows = elements(fa_node, "FaWiersz")
          raise ValidationError, "Invoice has no FaWiersz rows" if rows.empty? && required

          rows.map { |row| line_from(row) }
        end

        private

        def line_from(row)
          # **Gross pricing is the only shape still refused.** A row that simply states no
          # amount is read as one: {Line#net} answers nil, and tier 1 refuses such a row on an
          # invoice that derives its summary from its rows. A gross-priced row is different —
          # `P_9B`/`P_11A` carry a number this model has nowhere to put, so reading it would
          # drop a real amount rather than record its absence.
          raise ValidationError, priced_gross(row) if text(row, "P_11A") || text(row, "P_9B")

          # Passed as the strings they were written as; {Line} converts them, so decimal
          # coercion lives in one place rather than being repeated per caller.
          #
          # Every field here is `minOccurs="0"`, and all of them are now read leniently —
          # including `P_12`, which a simplified invoice's row omits. What a missing rate costs
          # is a summary bucket, which only matters when the invoice derives its summary; tier
          # 1 knows whether it does, and this does not.
          Line.new(
            name: text(row, "P_7"), unit: text(row, "P_8A"),
            quantity: text(row, "P_8B"), net_unit_price: text(row, "P_9A"),
            vat_rate: text(row, "P_12"), net_amount: text(row, "P_11"),
            row_number: text(row, "NrWierszaFa"), state_before: text(row, "StanPrzed")
          )
        end

        # Under art. 106e ust. 7-8 an invoice may state `P_9B` (unit gross price) and `P_11A`
        # (gross sales value) instead of `P_9A`/`P_11`, and two of the Ministry's own worked
        # examples do. This model carries net pricing only, so the amount has nowhere to go —
        # which is a limit of the model, not a fault in the document, and the message says so.
        def priced_gross(row)
          "FaWiersz #{text(row, "NrWierszaFa") || "(unnumbered)"} is priced gross, stating " \
            "P_11A/P_9B rather than P_11/P_9A. That is valid under art. 106e ust. 7-8, and this " \
            "model carries net pricing only (DESIGN.md §7.4) — the document itself is fine."
        end
      end
    end
  end
end
