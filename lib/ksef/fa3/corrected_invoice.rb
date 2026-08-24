# frozen_string_literal: true

module Ksef
  module FA3
    # One invoice a correction corrects (`DaneFaKorygowanej`).
    #
    # A `KOR` names at least one and may name up to **50 000** — art. 106j ust. 3 lets a
    # single correction carry a discount granted across a whole period, and the Ministry's
    # Przykład 6 does exactly that over six invoices with an `OkresFaKorygowanej` naming the
    # half-year (docs/REFERENCE.md §8.4).
    #
    # ## `ksef_number` is nil-able, and the nil is the point
    #
    # The schema puts a **choice** here: either `NrKSeF` + `NrKSeFFaKorygowanej`, or
    # `NrKSeFN` on its own — *"znacznik faktury korygowanej wystawionej poza KSeF"*, the
    # marker for an invoice issued outside the system. Both branches are single-valued
    # markers, so the whole choice is decided by whether a number is known. Modelling it as
    # one nil-able field makes emitting both branches, or neither, unrepresentable rather
    # than merely discouraged.
    CorrectedInvoice = Data.define(:number, :issue_date, :ksef_number) do
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      # @param number [String] `NrFaKorygowanej`, the corrected invoice's own number
      # @param issue_date [Date, String] `DataWystFaKorygowanej`
      # @param ksef_number [String, nil] `NrKSeFFaKorygowanej`; nil for an invoice issued
      #   outside KSeF, which emits `NrKSeFN` instead
      def initialize(number:, issue_date:, ksef_number: nil)
        # Coerced here rather than at serialisation, so an invoice built from a String and
        # the same invoice parsed back from XML are one object (§8.2b).
        super(number: number, issue_date: Formatting.to_date(issue_date), ksef_number: ksef_number)
      end

      def to_fa3
        {
          "DataWystFaKorygowanej" => Formatting.date(issue_date),
          "NrFaKorygowanej" => number
        }.merge(reference)
      end

      private

      # `TWybor1` has exactly one member, `"1"` — these are markers, not booleans, so there
      # is no "no" to write and the element is present or absent.
      def reference
        return { "NrKSeFN" => "1" } if ksef_number.nil?

        { "NrKSeF" => "1", "NrKSeFFaKorygowanej" => ksef_number }
      end
    end
  end
end
