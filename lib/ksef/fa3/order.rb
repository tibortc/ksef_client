# frozen_string_literal: true

module Ksef
  module FA3
    # The order or contract an advance invoice relates to (`Zamowienie`).
    #
    # Required by art. 106f ust. 1 pkt 4 on a `ZAL`, and the reason a `ZAL` has no `FaWiersz`
    # at all: the order positions take their place, in the currency the advance invoice was
    # issued in. A `KOR_ZAL` corrects those positions, showing before and after as separate
    # rows marked `StanPrzedZ` — the order's own version of `StanPrzed`.
    #
    # `total` is `WartoscZamowienia`, *"wartość zamówienia lub umowy z uwzględnieniem kwoty
    # podatku"* — the whole order **including tax**, not the amount this invoice covers. In the
    # Ministry's Przykład 10 it is 375 150 against an advance of 20 000, which is why it is
    # stated rather than summed from the rows and why it must never be confused with `P_15`.
    Order = Data.define(:total, :lines)

    # Construction and serialisation for {Ksef::FA3::Order}.
    class Order
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      NEEDS_LINES = "An order needs at least one position. `ZamowienieWiersz` is minOccurs=1 " \
                    "within `Zamowienie`, so an order without one cannot be serialised."

      # @param total [BigDecimal, Integer, String] `WartoscZamowienia`, including tax
      # @param lines [OrderLine, Array<OrderLine>] `ZamowienieWiersz`, at least one
      def initialize(total:, lines:)
        rows = Correction.wrap(lines)
        raise ValidationError, NEEDS_LINES if rows.empty?

        super(total: Formatting.decimal(total).round(Formatting::AMOUNT_SCALE),
              lines: self.class.positioned(rows).freeze)
      end

      # The same rule {Invoice.positioned} follows, for the same reason: a row number that
      # merely repeats its position carries nothing, and storing it would make an order built
      # with explicit numbering unequal to its own parsed form.
      def self.positioned(lines)
        lines.each_with_index.map do |line, index|
          next line unless line.is_a?(OrderLine) && line.row_number == index + 1

          line.with(row_number: nil)
        end
      end

      def to_fa3
        {
          "WartoscZamowienia" => Formatting.amount(total),
          "ZamowienieWiersz" => lines.each_with_index.map { |line, index| line.to_fa3(row_number: index + 1) }
        }
      end
    end
  end
end
