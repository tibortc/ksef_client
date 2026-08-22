# frozen_string_literal: true

require "bigdecimal"
require "date"

module Ksef
  module FA3
    # Value formatting for FA(3) documents (DESIGN.md §7.5).
    #
    # Centralised deliberately: every monetary amount, date and flag in the document goes
    # through here, so the rules live in one place rather than being reinvented per field.
    module Formatting
      # Amounts are written with exactly two decimal places. `BigDecimal#to_s` would emit
      # scientific notation ("0.15e4"), which the schema's decimal types reject.
      AMOUNT_SCALE = 2

      # Rate codes are not all numeric — "0 KR", "zw", "oo", "np I" are valid members of
      # TStawkaPodatku (docs/REFERENCE.md §8.1). They pass through untouched.
      class << self
        # @param value [BigDecimal, Integer, String]
        # @return [String] a fixed-point decimal string with exactly {AMOUNT_SCALE} places
        # @raise [Ksef::ValidationError] if given a Float
        def amount(value)
          # `BigDecimal#to_s("F")` drops trailing zeros, so 1500 becomes "1500.0" — legal
          # xsd:decimal but wrong for a currency amount, and confusing to anyone reading
          # the invoice. Padding is done on the string rather than with format("%.2f"),
          # which would route the value through Float and defeat the point of BigDecimal.
          integer, fraction = decimal(value).round(AMOUNT_SCALE).to_s("F").split(".")
          "#{integer}.#{fraction.to_s.ljust(AMOUNT_SCALE, "0")[0, AMOUNT_SCALE]}"
        end

        # Quantities allow more precision than amounts, so they keep their own scale
        # rather than being rounded to two places.
        def quantity(value)
          formatted = decimal(value).to_s("F")
          # `to_s("F")` gives "10.0"; the schema is happy either way, but trailing ".0"
          # reads oddly on a count of hours.
          formatted.sub(/\.0\z/, "")
        end

        # @return [String] ISO-8601 date, e.g. "2026-08-22"
        def date(value)
          coerce_date(value).strftime("%Y-%m-%d")
        end

        # @return [String] xsd:dateTime in UTC, e.g. "2026-08-22T10:00:00Z"
        def date_time(value)
          case value
          when String then value
          when DateTime then value.new_offset(0).strftime("%Y-%m-%dT%H:%M:%SZ")
          when Date then value.strftime("%Y-%m-%dT00:00:00Z")
          else value.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
          end
        end

        # The schema spells booleans as etd:TWybor1_2, where "1" is yes and "2" is no.
        # Emitting "true" or "0" would be schema-invalid, and the inversion is easy to get
        # backwards, so it lives here rather than at each call site.
        def flag(value)
          case value
          when true, "1", 1 then "1"
          when false, nil, "2", 2 then "2"
          else raise ValidationError, "Expected a boolean-ish value for a 1/2 flag, got #{value.inspect}"
          end
        end

        # @raise [Ksef::ValidationError] Float is forbidden in any monetary path
        #   (DESIGN.md §4.4) — binary floating point cannot represent 0.01 exactly, and
        #   a rounding error in a tax document is a real problem.
        def decimal(value)
          case value
          when BigDecimal then value
          when Integer, String then BigDecimal(value)
          # Rational needs an explicit precision; the others do not.
          when Rational then BigDecimal(value, AMOUNT_SCALE + 10)
          when Float
            raise ValidationError,
                  "Float is not allowed for monetary or quantity values (got #{value.inspect}). " \
                  "Use a BigDecimal, an Integer, or a decimal String."
          else
            raise ValidationError, "Cannot convert #{value.class} to a decimal: #{value.inspect}"
          end
        end

        private

        def coerce_date(value)
          case value
          when Date then value
          when String then Date.parse(value)
          else value.to_date
          end
        end
      end
    end
  end
end
