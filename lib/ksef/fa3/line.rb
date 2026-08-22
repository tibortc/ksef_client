# frozen_string_literal: true

module Ksef
  module FA3
    # One invoice line (`FaWiersz`).
    #
    # Amounts are `BigDecimal` throughout. `Float` is rejected rather than coerced
    # (DESIGN.md §4.4): binary floating point cannot represent 0.01 exactly, and a
    # rounding error in a tax document is a real problem, not a cosmetic one.
    #
    # `vat_rate` is a **string code** from `TStawkaPodatku`, not a number. Half of the
    # fourteen permitted values are not numeric — "0 WDT", "zw", "oo", "np I" — so the
    # rate is carried verbatim and only looked up when a bucket is needed
    # (docs/REFERENCE.md §8.1a).
    Line = Data.define(:name, :quantity, :unit, :net_unit_price, :vat_rate, :net_amount) do
      def initialize(name:, quantity:, unit:, net_unit_price:, vat_rate:, net_amount: nil)
        super
      end

      # Computed unless overridden — ERP-as-source-of-truth callers can supply their own
      # figure and have it round-tripped verbatim (DESIGN.md §7.3).
      def net
        return Formatting.decimal(net_amount) if net_amount

        Formatting.decimal(quantity) * Formatting.decimal(net_unit_price)
      end

      # @return [BigDecimal] tax on this line, or zero for a non-numeric rate code
      def vat
        percentage = VatRate.percentage(vat_rate)
        return BigDecimal(0) unless percentage

        (net * percentage / 100).round(Formatting::AMOUNT_SCALE)
      end

      def gross = net + vat

      def to_fa3(row_number:)
        {
          "NrWierszaFa" => row_number,
          "P_7" => name,
          "P_8A" => unit,
          "P_8B" => Formatting.quantity(quantity),
          "P_9A" => Formatting.amount(net_unit_price),
          "P_11" => Formatting.amount(net),
          "P_12" => vat_rate.to_s
        }
      end
    end
  end
end
