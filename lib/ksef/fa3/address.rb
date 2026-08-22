# frozen_string_literal: true

module Ksef
  module FA3
    # A subject's address.
    #
    # FA(3) does not model an address as structured fields. `AdresL1` and `AdresL2` are
    # free-text lines of up to 512 characters, so the structured attributes here are a
    # convenience that is composed down to those lines on serialisation. Callers who
    # already hold a formatted address can pass `line1` directly instead.
    Address = Data.define(:line1, :line2, :country, :street, :city, :postal_code) do
      def initialize(line1: nil, line2: nil, country: "PL", street: nil, city: nil, postal_code: nil)
        super
      end

      # @return [String] the composed first address line
      def to_line1
        return line1 if line1

        composed = [street, [postal_code, city].compact.join(" ").strip].reject { |p| p.nil? || p.empty? }
        raise ValidationError, "Address needs either line1, or street/city/postal_code" if composed.empty?

        composed.join(", ")
      end

      def to_fa3
        content = { "KodKraju" => country, "AdresL1" => to_line1 }
        content["AdresL2"] = line2 if line2
        content
      end
    end
  end
end
