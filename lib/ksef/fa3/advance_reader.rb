# frozen_string_literal: true

module Ksef
  module FA3
    # Reads the two elements that make an invoice part of an advance-payment sequence:
    # `Zamowienie`, the order a `ZAL` collects against, and `FakturaZaliczkowa`, the advance
    # invoices a `ROZ` settles (docs/REFERENCE.md §8.5).
    #
    # Split out for the reason {CorrectionReader} is: it is the part of reading an invoice that
    # is entirely about one family of types.
    module AdvanceReader
      class << self
        # Namespace-aware element reading; see {NodeReader}.
        include NodeReader

        # @return [Order, nil]
        def order_from(fa_node)
          node = element(fa_node, "Zamowienie")
          return nil if node.nil?

          Order.new(total: text!(node, "WartoscZamowienia"),
                    lines: elements(node, "ZamowienieWiersz").map { |row| order_line_from(row) })
        end

        # @return [Array<AdvanceInvoice>] empty when the invoice settles nothing
        def advances_from(fa_node)
          elements(fa_node, "FakturaZaliczkowa").map { |node| advance_from(node) }
        end

        private

        def order_line_from(row)
          OrderLine.new(
            name: text(row, "P_7Z"), unit: text(row, "P_8AZ"), quantity: text(row, "P_8BZ"),
            net_unit_price: text(row, "P_9AZ"), net_amount: text(row, "P_11NettoZ"),
            vat_amount: text(row, "P_11VatZ"), vat_rate: text(row, "P_12Z"),
            row_number: text(row, "NrWierszaZam"), state_before: text(row, "StanPrzedZ")
          )
        end

        # The schema's choice, read the way {CorrectionReader.reference_from} reads its own:
        # a document stating neither branch is refused rather than being repaired into one,
        # since choosing for it would assert something nobody wrote.
        def advance_from(node)
          ksef_number = text(node, "NrKSeFFaZaliczkowej")
          return AdvanceInvoice.new(ksef_number: ksef_number) if ksef_number

          number = text(node, "NrFaZaliczkowej")
          return AdvanceInvoice.new(number: number) if number

          raise ValidationError,
                "FakturaZaliczkowa states neither NrKSeFFaZaliczkowej nor NrFaZaliczkowej. " \
                "The schema requires one of the two, and picking one would assert where the " \
                "advance invoice was issued."
        end
      end
    end
  end
end
