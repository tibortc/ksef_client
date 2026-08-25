# frozen_string_literal: true

module Ksef
  module FA3
    # One position of the order or contract an advance invoice relates to
    # (`Zamowienie/ZamowienieWiersz`).
    #
    # ## Nothing here is derived, and that is the difference from {Line}
    #
    # {Line#net} computes a net from quantity × price when the document does not state one,
    # because a `VAT` invoice's tax summary is computed *from* its rows. An order's rows feed
    # nothing: `WartoscZamowienia` is stated, and so are the invoice's own buckets — every type
    # that carries a `Zamowienie` is in {Invoice::STATED_TOTALS_TYPES}. So a derivation here
    # would have no consumer, and inventing an amount the contract does not state is the thing
    # this model spends its effort avoiding (docs/REFERENCE.md §8.5).
    #
    # The tax is stated too, in `P_11VatZ` — *"kwota podatku od zamówionego towaru lub
    # usługi"*. `FaWiersz` has no such element and the tax is computed from the rate; here the
    # document carries both, so both are read.
    OrderLine = Data.define(:name, :quantity, :unit, :net_unit_price, :net_amount, :vat_amount,
                            :vat_rate, :row_number, :state_before) do
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      # Every element of `ZamowienieWiersz` except `NrWierszaZam` is `minOccurs="0"`, so every
      # field here is optional and an absent one is omitted rather than written empty.
      #
      # `P_9AZ` is `TKwotowy2`, not `TKwotowy` — the same eight-place unit price as {Line}'s
      # `P_9A`, and rounded to the same scale for the same reason.
      def initialize(name: nil, quantity: nil, unit: nil, net_unit_price: nil, net_amount: nil,
                     vat_amount: nil, vat_rate: nil, row_number: nil, state_before: false)
        super(
          name: Formatting.text(name), unit: Formatting.text(unit),
          vat_rate: Formatting.text(vat_rate),
          quantity: Line.scaled(quantity, Formatting::QUANTITY_SCALE),
          net_unit_price: Line.scaled(net_unit_price, Formatting::UNIT_PRICE_SCALE),
          net_amount: Line.scaled(net_amount, Formatting::AMOUNT_SCALE),
          vat_amount: Line.scaled(vat_amount, Formatting::AMOUNT_SCALE),
          row_number: row_number.nil? ? nil : Formatting.integer(row_number),
          state_before: Formatting.unflag(state_before)
        )
      end

      # `StanPrzedZ` is `StanPrzed`'s twin for an order position: a `KOR_ZAL` shows a corrected
      # position before and after as separate rows. Same shape, same pairing by row number.
      #
      # @param row_number [Integer] the row's position, used when the line states none itself
      def to_fa3(row_number:)
        {
          "NrWierszaZam" => self.row_number || row_number,
          "P_7Z" => name,
          "P_8AZ" => unit,
          "P_12Z" => vat_rate,
          "StanPrzedZ" => state_before ? Formatting.flag(true) : nil
        }.merge(amounts).compact
      end

      private

      def amounts
        {
          "P_8BZ" => quantity && Formatting.quantity(quantity),
          "P_9AZ" => net_unit_price && Formatting.unit_price(net_unit_price),
          "P_11NettoZ" => net_amount && Formatting.amount(net_amount),
          "P_11VatZ" => vat_amount && Formatting.amount(vat_amount)
        }
      end
    end
  end
end
