# frozen_string_literal: true

module Ksef
  module FA3
    # Polish tax identifier (NIP) validation (DESIGN.md §7.2).
    #
    # Worth validating locally rather than letting KSeF reject the invoice: a mistyped NIP
    # is one of the likeliest data-entry errors, and the round trip to find out is slow.
    module NIP
      # Positional weights for digits 1-9. The weighted sum mod 11 must equal digit 10.
      WEIGHTS = [6, 5, 7, 2, 3, 4, 5, 6, 7].freeze
      LENGTH = 10

      class << self
        # Accepts the common written forms — "123-456-32-18", "PL1234563218" — since that
        # is how a NIP arrives from an ERP or a human.
        #
        # @return [String] ten digits
        def normalize(value)
          value.to_s.strip.sub(/\A[Pp][Ll]/, "").gsub(/[\s-]/, "")
        end

        # @return [Boolean]
        def valid?(value)
          digits = normalize(value)
          return false unless /\A\d{#{LENGTH}}\z/o.match?(digits)

          checksum(digits) == digits[9].to_i
        end

        # @raise [Ksef::ValidationError] with the reason, since "invalid NIP" alone does
        #   not tell a user whether they mistyped a digit or pasted the wrong field
        def validate!(value, field: "NIP")
          digits = normalize(value)

          unless /\A\d{#{LENGTH}}\z/o.match?(digits)
            raise ValidationError,
                  "#{field} must be #{LENGTH} digits, got #{value.inspect} " \
                  "(#{digits.length} digit(s) after normalisation)"
          end

          expected = checksum(digits)
          return digits if expected == digits[9].to_i

          raise ValidationError,
                "#{field} #{digits} has an invalid check digit: expected #{expected}, got #{digits[9]}"
        end

        private

        # A weighted sum of 10 means no valid check digit exists, so such a number can
        # never be a NIP. Returning 10 makes the comparison fail, which is correct.
        def checksum(digits)
          WEIGHTS.each_with_index.sum { |weight, index| weight * digits[index].to_i } % 11
        end
      end
    end
  end
end
