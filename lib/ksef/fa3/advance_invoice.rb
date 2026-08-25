# frozen_string_literal: true

module Ksef
  module FA3
    # An advance invoice a settlement invoice settles (`FakturaZaliczkowa`).
    #
    # A `ROZ` — the invoice of art. 106f ust. 3, issued once the goods are delivered — names
    # every advance invoice already issued for the same transaction, up to **100** of them.
    #
    # ## The choice is inverted from {CorrectedInvoice}'s, and that is the schema's doing
    #
    # `DaneFaKorygowanej` pairs its *marker* with the KSeF number. `FakturaZaliczkowa` pairs it
    # with the plain one:
    #
    # - in KSeF → `NrKSeFFaZaliczkowej` alone, *"numer identyfikujący fakturę zaliczkową w
    #   KSeF"*;
    # - outside KSeF → `NrKSeFZN`, *"znacznik faktury zaliczkowej wystawionej poza KSeF"*,
    #   followed by `NrFaZaliczkowej`, the number it carried on paper.
    #
    # So the two branches name *different fields*, and modelling it as one nil-able value would
    # lose which. Both are carried, and exactly one must be given — checked here, so a document
    # naming both or neither cannot be built.
    AdvanceInvoice = Data.define(:ksef_number, :number)

    # Reopened rather than using a `Data.define` block, so the constant below lands on the
    # class *and* resolves from inside `#initialize` — a block body's constant lookup is
    # lexical, against `Ksef::FA3`, so `ONE_OF` defined on the class would not be found there.
    class AdvanceInvoice
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      ONE_OF = "An advance invoice is named by exactly one of ksef_number: (its KSeF number) " \
               "or number: (its own number, for one issued outside KSeF). The schema puts a " \
               "choice here, so naming both or neither is not a document that exists."

      # @param ksef_number [String, nil] `NrKSeFFaZaliczkowej`, for an advance invoice issued
      #   through KSeF
      # @param number [String, nil] `NrFaZaliczkowej`, for one issued outside it
      # @raise [Ksef::ValidationError] unless exactly one of the two is given
      def initialize(ksef_number: nil, number: nil)
        given = [ksef_number, number].compact
        raise ValidationError, ONE_OF unless given.size == 1

        super(ksef_number: Formatting.text(ksef_number), number: Formatting.text(number))
      end

      def to_fa3
        return { "NrKSeFFaZaliczkowej" => ksef_number } if ksef_number

        # `TWybor1` has one member: the marker is present or absent, with no "no" to write.
        { "NrKSeFZN" => "1", "NrFaZaliczkowej" => number }
      end
    end
  end
end
