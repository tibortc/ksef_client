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
      include Canonical

      # The three numeric fields are converted **on the way in**, so "amounts are BigDecimal
      # throughout" is an invariant of the object rather than a promise kept by whichever
      # method happens to look at them next.
      #
      # Two things follow. A `Float` is rejected at construction, where the caller can see
      # which line it passed, instead of at serialisation. And a line built with `quantity:
      # 10` is genuinely the same object as one parsed back as `BigDecimal("10")` — without
      # this they compare equal (`Data#==` uses `==` per member) while hashing differently,
      # which breaks them as Hash keys and makes DESIGN.md §7.6's round-trip law hold for
      # `==` but not for `#hash`.
      # They are also rounded to the scale their element permits: `TKwotowy` is
      # `fractionDigits="2"` and `TIlosci` is `fractionDigits="6"`, so a unit price of
      # `150.125` is not a value FA(3) can express. Rounding it here rather than at
      # serialisation means the model reports the figure the document will actually carry —
      # the same rule as everything else in §8.2b. It also makes `#net` agree with the
      # invoice as printed: deriving a net from a price finer than the one shown produced a
      # line whose own arithmetic did not add up.
      def initialize(name:, quantity:, unit:, net_unit_price:, vat_rate:, net_amount: nil)
        super(
          name: name, unit: unit, vat_rate: vat_rate,
          quantity: self.class.scaled(quantity, Formatting::QUANTITY_SCALE),
          net_unit_price: self.class.scaled(net_unit_price, Formatting::AMOUNT_SCALE),
          net_amount: self.class.scaled(net_amount, Formatting::AMOUNT_SCALE)
        )
      end

      # Quantity and unit price are both optional in `TFaWiersz`, so nil has to survive.
      def self.scaled(value, scale) = value.nil? ? nil : Formatting.decimal(value).round(scale)

      # Computed unless overridden — ERP-as-source-of-truth callers can supply their own
      # figure and have it round-tripped verbatim (DESIGN.md §7.3). A parsed line always
      # states it, because `P_11` is in the document and may disagree with quantity × price.
      def net
        return net_amount unless net_amount.nil?

        if quantity.nil? || net_unit_price.nil?
          raise ValidationError,
                "Line #{name.inspect} needs either net_amount, or both quantity and net_unit_price"
        end

        quantity * net_unit_price
      end

      # @return [BigDecimal] tax on this line, or zero for a non-numeric rate code
      def vat
        percentage = VatRate.percentage(vat_rate)
        return BigDecimal(0) unless percentage

        (net * percentage / 100).round(Formatting::AMOUNT_SCALE)
      end

      def gross = net + vat

      # Every child of `TFaWiersz` except `NrWierszaFa` is `minOccurs="0"`, and the parser
      # accepts a row that states only its net. Absent fields are therefore **omitted**, not
      # written empty: `<P_8A/>` fails `TZnakowy`'s minimum length, so emitting one turned a
      # schema-valid lump-sum row into an invalid document — and formatting a nil quantity
      # raised, which took {Provenance#unmapped_elements} down with it, since that serialises
      # to work out what it would lose. Same rule {Subject} follows for an absent `Nazwa`.
      def to_fa3(row_number:)
        {
          "NrWierszaFa" => row_number,
          "P_7" => name,
          "P_8A" => unit,
          "P_8B" => quantity && Formatting.quantity(quantity),
          "P_9A" => net_unit_price && Formatting.amount(net_unit_price),
          "P_11" => Formatting.amount(net),
          "P_12" => vat_rate&.to_s
        }.compact
      end
    end
  end
end
