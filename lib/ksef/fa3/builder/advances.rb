# frozen_string_literal: true

module Ksef
  module FA3
    class Builder
      # The DSL calls for the advance-payment family — the order a `ZAL` collects against and
      # the advance invoices a `ROZ` settles (docs/REFERENCE.md §8.5).
      #
      # Mixed into {Builder}, so `@order`, `@order_lines` and `@advances` are its state.
      module Advances
        # The order or contract an advance invoice collects against (`Zamowienie`, art. 106f
        # ust. 1 pkt 4). Sets the order's own total; call {#order_line} for its positions.
        #
        # @param attributes [Hash] `:total` — the whole order **including tax**, which is not
        #   what this invoice charges. See {Order}.
        def order(**attributes)
          @order = normalise(attributes, ORDER_KEYS, {}, "order")
        end

        # Appends one position of the order. Nothing here is derived — see {OrderLine}.
        #
        # @param attributes [Hash] `:name`, `:quantity` (or `:qty`), `:unit`, `:net_unit_price`,
        #   `:net_amount`, `:vat_amount`, `:vat_rate` (or `:vat`), `:row_number`, `:state_before`
        def order_line(**attributes)
          @order_lines << OrderLine.new(**normalise(attributes, ORDER_LINE_KEYS, LINE_ALIASES, "order line"))
        end

        # Names one advance invoice this settlement invoice settles (`FakturaZaliczkowa`). Call
        # once per advance invoice; art. 106f ust. 3 allows up to a hundred.
        #
        # @param attributes [Hash] exactly one of `:ksef_number` (issued through KSeF) or
        #   `:number` (issued outside it)
        def settles(**attributes)
          @advances << AdvanceInvoice.new(**normalise(attributes, ADVANCE_KEYS, {}, "settles"))
        end

        private

        # Assembled at the end for the reason {#assembled_correction} is: an order is only
        # well-formed once it has both a total and a position, and the DSL supplies them
        # separately. `total:` is checked here rather than left to `Order.new`, which would
        # otherwise raise `ArgumentError: missing keyword` — outside this gem's hierarchy.
        def assembled_order
          return nil if @order.nil? && @order_lines.empty?
          unless @order&.key?(:total)
            raise ValidationError,
                  "An order needs a total: the value of the whole order including tax " \
                  "(`WartoscZamowienia`). Pass it to `order` — `order_line` alone does not " \
                  "imply one, and the schema makes it mandatory."
          end

          Order.new(total: @order[:total], lines: @order_lines)
        end
      end
    end
  end
end
