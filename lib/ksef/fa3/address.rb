# frozen_string_literal: true

module Ksef
  module FA3
    # A subject's address (`TAdres`).
    #
    # FA(3) does not model an address as structured fields, and neither does this. `TAdres`
    # is `KodKraju` + `AdresL1` + optional `AdresL2` + optional `GLN`, where the two address
    # lines are free text of up to 512 characters.
    #
    # **That shape is upstream's, not a simplification of it.** The only official code that
    # reads an FA(3) address is `ksef-pdf-generator`'s `FA3/Adres.ts`, which models exactly
    # those four elements; neither the C# nor the Java client models FA(3) at all, both
    # taking the document as bytes. There is no upstream notion of a street or a postal code.
    #
    # So `street`, `city` and `postal_code` are **constructor conveniences, not state**: they
    # compose into `line1` on the way in and are not retained. Retaining them would imply
    # the document can express them, and would make an address built from parts unequal to
    # the identical address given as a line — a distinction FA(3), KSeF and any reader of the
    # invoice are all blind to, and one that would break DESIGN.md §7.6's round-trip law for
    # the most ordinary use of the builder (docs/REFERENCE.md §8.2b).
    #
    # `GLN` is deliberately not carried: it is optional, nothing here needs it, and a parsed
    # document that has one reports it through {Invoice#unmapped_elements} rather than
    # losing it quietly.
    Address = Data.define(:line1, :line2, :country) do
      include Canonical

      # @param line1 [String, nil] a formatted address line, for callers who have one
      # @param line2 [String, nil] `AdresL2`, omitted from the document when nil
      # @param country [String] `KodKraju`, ISO 3166-1 alpha-2
      # @param street [String, nil] composed into `line1` together with the two below
      # @param city [String, nil]
      # @param postal_code [String, nil]
      # @raise [Ksef::ValidationError] if there is no way to produce the mandatory `AdresL1`
      def initialize(line1: nil, line2: nil, country: "PL", street: nil, city: nil, postal_code: nil)
        composed = line1 || self.class.compose(street: street, city: city, postal_code: postal_code)
        # `AdresL1` is mandatory in `TAdres`, so an address without one can never serialise.
        # Refusing it at construction puts the error where the mistake is, rather than
        # surfacing it later from `#to_fa3` on an invoice that looks complete.
        raise ValidationError, "Address needs either line1, or street/city/postal_code" if composed.nil?

        super(line1: Formatting.text(composed), line2: Formatting.text(line2),
              country: Formatting.text(country))
      end

      def to_fa3
        content = { "KodKraju" => country, "AdresL1" => line1 }
        content["AdresL2"] = line2 unless line2.nil?
        content
      end

      # `"Prosta 1, 00-001 Warszawa"` — street, then postal code and city, skipping whatever
      # is absent so a partial address still yields something usable.
      #
      # @return [String, nil] nil when there is nothing to compose from
      def self.compose(street:, city:, postal_code:)
        locality = [postal_code, city].compact.join(" ").strip
        parts = [street, locality].reject { |part| part.nil? || part.empty? }
        parts.empty? ? nil : parts.join(", ")
      end
    end
  end
end
