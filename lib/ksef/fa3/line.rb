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
    #
    # `row_number` and `state_before` exist for corrections and are inert everywhere else;
    # see {#initialize} and {#to_fa3}.
    Line = Data.define(:name, :quantity, :unit, :net_unit_price, :vat_rate, :net_amount,
                       :row_number, :state_before) do
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
      # They are also rounded to the scale their element permits, and **the three elements do
      # not share one**: `P_11` is `TKwotowy` (`fractionDigits="2"`), `P_8B` is `TIlosci`
      # (`6`), and `P_9A` is **`TKwotowy2` (`8`)** — a unit price is allowed four times the
      # precision of the amount it produces. Rounding here rather than at serialisation means
      # the model reports the figure the document will actually carry — the same rule as
      # everything else in §8.2b. It also makes `#net` agree with the invoice as printed:
      # deriving a net from a price finer than the one shown produced a line whose own
      # arithmetic did not add up.
      #
      # Reading `P_9A` at two places was a silent alteration of a stated amount, invisible to
      # every tier; see {Formatting::UNIT_PRICE_SCALE}.
      #
      # ## The two correction fields
      #
      # `state_before` writes `StanPrzed`, the marker for *"stan przed korektą"*: a `KOR` may
      # show a corrected position twice, once as it was and once as it now is. It is a flag on
      # the row and changes no arithmetic here — {Invoice} takes a correction's summaries from
      # {Totals} rather than deriving them (docs/REFERENCE.md §8.4).
      #
      # `row_number` is **nil for an ordinary line, and nil means "number me by position"**.
      # It is stored only when a row's `NrWierszaFa` is *not* its index, which happens exactly
      # where it carries information: the Ministry's Przykład 2 numbers a before/after pair
      # `1` and `1`, and after `UU_ID` is dropped that shared number is the only thing left
      # linking them. Storing the number unconditionally would make a parsed ordinary invoice
      # unequal to the built invoice it came from, and DESIGN.md §7.6's round-trip law with
      # it.
      # Every child of `FaWiersz` but `NrWierszaFa` is `minOccurs="0"`, so every field here is
      # optional — a simplified invoice's row states a name and nothing else. `name:` stays a
      # required *keyword* rather than gaining a default, because a row that names nothing at
      # all is a caller mistake far more often than it is a document; pass `name: nil`
      # deliberately if a document really omits `P_7`, which the parser does.
      def initialize(name:, quantity: nil, unit: nil, net_unit_price: nil, vat_rate: nil,
                     net_amount: nil, row_number: nil, state_before: false)
        super(
          # `TZnakowy`/`TStawkaPodatku` are token types, so these are canonicalised the way
          # every other field is (§8.2b). `vat_rate` matters most: {VatRate.bucket} looks the
          # code up exactly, so an uncollapsed `" 23 "` passed tier 1 — which collapses before
          # checking membership — and then made `#to_xml` raise.
          name: Formatting.text(name), unit: Formatting.text(unit),
          vat_rate: Formatting.text(vat_rate),
          quantity: self.class.scaled(quantity, Formatting::QUANTITY_SCALE),
          net_unit_price: self.class.scaled(net_unit_price, Formatting::UNIT_PRICE_SCALE),
          net_amount: self.class.scaled(net_amount, Formatting::AMOUNT_SCALE),
          row_number: row_number.nil? ? nil : Formatting.integer(row_number),
          # Canonicalised to a boolean so `"1"` from a document and `true` from a builder are
          # one value, and so `#to_fa3` cannot be handed something `Formatting.flag` refuses.
          state_before: Formatting.unflag(state_before)
        )
      end

      # Quantity and unit price are both optional in `FaWiersz`, so nil has to survive.
      def self.scaled(value, scale) = value.nil? ? nil : Formatting.decimal(value).round(scale)

      # Computed unless overridden — ERP-as-source-of-truth callers can supply their own
      # figure and have it round-tripped verbatim (DESIGN.md §7.3). A parsed line usually
      # states it, because `P_11` is in the document and may disagree with quantity × price.
      #
      # **`nil` when the row states no amount, which is legal** and not the same as zero. A
      # simplified invoice under art. 106e ust. 5 pkt 3 names the goods and nothing else —
      # both of the Ministry's `UPR` samples do — and a collective correction's descriptive
      # row does the same. Such a row contributes nothing to a summary, which is why every
      # type that carries one states its summary instead ({Invoice::STATED_TOTALS_TYPES}), and
      # why tier 1 refuses one on an invoice that derives its summary from its rows: the
      # amount would otherwise be silently absent from the tax base.
      #
      # This used to raise. It could, while every modelled type priced its rows; it cannot
      # now, because "the row states no amount" is a thing the model has to be able to hold.
      # @return [BigDecimal, nil]
      def net
        return net_amount unless net_amount.nil?
        return nil if quantity.nil? || net_unit_price.nil?

        quantity * net_unit_price
      end

      # @return [Boolean] whether this row states an amount at all
      def priced? = !net.nil?

      # Whether this row can be placed in a summary bucket: it needs an amount *and* a rate to
      # put it under. {ModelValidator} refuses a row that cannot, on an invoice that derives.
      def summarised? = priced? && !vat_rate.nil?

      # Tax on this line. The two absences here are **not the same absence**, and answering
      # one figure for both stated something false:
      #
      # - a non-numeric rate code (`zw`, `oo`, `np I`, `0 WDT`) carries **no tax**, which is a
      #   known quantity, and zero is the right answer;
      # - a row that states no amount has **unknown** tax, and zero claimed it was nothing.
      #
      # `#net` and `#gross` already answered nil for the second case, so `#vat` was the one
      # method contradicting the rule the rest of the model follows.
      #
      # @return [BigDecimal, nil] nil for a row that states no amount to tax
      def vat
        return nil if net.nil?

        percentage = VatRate.percentage(vat_rate)
        return BigDecimal(0) if percentage.nil?

        (net * percentage / 100).round(Formatting::AMOUNT_SCALE)
      end

      # @return [BigDecimal, nil] nil for a row that states no amount
      def gross = net.nil? ? nil : net + vat

      # Every child of `FaWiersz` except `NrWierszaFa` is `minOccurs="0"`, and the parser
      # accepts a row that states only its net. Absent fields are therefore **omitted**, not
      # written empty: `<P_8A/>` fails `TZnakowy`'s minimum length, so emitting one turned a
      # schema-valid lump-sum row into an invalid document — and formatting a nil quantity
      # raised, which took {Provenance#unmapped_elements} down with it, since that serialises
      # to work out what it would lose. Same rule {Subject} follows for an absent `Nazwa`.
      #
      # @param row_number [Integer] the row's position, used when the line does not state a
      #   number of its own
      def to_fa3(row_number:)
        {
          "NrWierszaFa" => self.row_number || row_number,
          "P_7" => name,
          "P_8A" => unit,
          "P_8B" => quantity && Formatting.quantity(quantity),
          "P_9A" => net_unit_price && Formatting.unit_price(net_unit_price),
          "P_11" => net && Formatting.amount(net),
          "P_12" => vat_rate,
          # `TWybor1` has one member: the marker is present or it is absent, and there is no
          # "no" to write.
          "StanPrzed" => state_before ? Formatting.flag(true) : nil
        }.compact
      end
    end
  end
end
