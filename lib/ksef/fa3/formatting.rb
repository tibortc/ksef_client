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

      # `TIlosci` is `fractionDigits="6"`. Quantities are allowed more precision than amounts,
      # but not unlimited precision, and exceeding it is a schema rejection rather than a
      # rounding difference.
      QUANTITY_SCALE = 6

      # Significant digits used when converting a Rational. The widest FA(3) numeric type is
      # `TIlosci` at `totalDigits="22"`, so 30 clears every value the schema permits with room
      # to spare — unlike `AMOUNT_SCALE + 10`, which read as "12 decimal places" but means
      # "12 significant digits" and truncated anything above ten billion.
      RATIONAL_PRECISION = 30

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

        # Quantities allow more precision than amounts, so they keep their own scale rather
        # than being rounded to two places — but they are not unbounded: `TIlosci` is
        # `fractionDigits="6"`, so eight decimal places produce a schema-invalid document.
        def quantity(value)
          formatted = decimal(value).round(QUANTITY_SCALE).to_s("F")
          # `to_s("F")` gives "10.0"; the schema is happy either way, but trailing ".0"
          # reads oddly on a count of hours.
          formatted.sub(/\.0\z/, "")
        end

        # @return [String] ISO-8601 date, e.g. "2026-08-22"
        def date(value)
          to_date(value).strftime("%Y-%m-%d")
        end

        # @param value [Date, String, #to_date]
        # @return [Date]
        # @raise [Ksef::ValidationError] rather than `Date::Error`, so a caller rescuing this
        #   gem's own hierarchy — which is what the docs tell them to do — actually catches a
        #   malformed date read out of a document
        # A String must be ISO-8601. `Date.parse` guesses, and its guesses are worse than a
        # refusal: `"junk"` reads as June and answers the first of that month in the *current*
        # year, and `"12"` answers the twelfth of the current month — a value that changes with
        # the clock. Every date in an FA(3) document is `etd:TData`, i.e. `xsd:date`, so the
        # strict reading is also the only one a document can contain.
        def to_date(value)
          return Date.iso8601(value) if value.is_a?(String)
          # `instance_of?`, not `is_a?`: a DateTime *is* a Date, but it carries a time of day, and
          # leaving one in place makes every date comparison depend on the clock — `DateTime.now
          # + 1` sorts after `Date.today + 1`, so a one-day tolerance quietly shrinks by however
          # late in the day it is.
          return value if value.instance_of?(Date)

          value.to_date
        # `Date::Error` is itself an `ArgumentError`, so listing both would shadow it.
        # `NoMethodError` covers an object with no `#to_date`.
        rescue ArgumentError, TypeError, NoMethodError => e
          raise ValidationError, "Cannot read #{value.inspect} as a date: #{e.message}"
        end

        # @return [String] xsd:dateTime in UTC, e.g. "2026-08-22T10:00:00Z"
        def date_time(value)
          case value
          when String then value
          when DateTime then value.new_offset(0).strftime("%Y-%m-%dT%H:%M:%SZ")
          when Date then value.strftime("%Y-%m-%dT00:00:00Z")
          # Anything else is asked for `#utc`. An object that has none is a caller mistake, and
          # it must arrive as a ValidationError rather than as a bare NoMethodError from inside
          # the serializer — the same contract {.to_date} and {.decimal} keep.
          else utc_string(value)
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

        # The inverse of {.flag}, for the parser.
        #
        # `nil` reads as false, which is not laxity: for `JST` and `GV` the seller has no
        # such element at all, and a buyer that omits them means "no". Anything else raises,
        # because a third value in a 1/2 field is a document we do not understand rather
        # than one we should guess at.
        def unflag(value)
          case value
          when "1", 1, true then true
          when "2", 2, nil, false then false
          else raise ValidationError, "Expected a 1/2 flag, got #{value.inspect}"
          end
        end

        # For the handful of elements restricting `xsd:integer` — `TypKorekty`, `NrWierszaFa`.
        #
        # `Integer()` rather than `#to_i`, which answers 0 for "abc" and would turn a
        # malformed document into a plausible one. The failure arrives as a ValidationError
        # for the same reason {.to_date} and {.decimal} do: a caller rescuing this gem's own
        # hierarchy has to catch it.
        #
        # **Base 10 is explicit, and the reason is a shipped bug.** `Integer("010")` is *eight*
        # — Ruby honours a leading zero as octal, `0x` as hex and `0b` as binary. `NrWierszaFa`
        # is `TNaturalny`, whose lexical space permits leading zeros, so `<NrWierszaFa>010`
        # meant ten, parsed as eight, and re-serialised as `8`: a silently renumbered row on a
        # schema-valid document, in a field that is the only thing pairing a correction's
        # before/after rows. `"08"` failed the other way, raising on a document the schema
        # accepts. Found by audit 2026-08-24 (docs/REFERENCE.md §8.4b).
        #
        # A `Float` is refused rather than truncated: `Integer(2.9)` is 2, and silently
        # changing a caller's value is the thing this method exists to prevent.
        def integer(value)
          raise ValidationError, "Float is not allowed for a whole number (got #{value.inspect})" if value.is_a?(Float)

          value.is_a?(String) ? Integer(value, 10) : Integer(value)
        rescue ArgumentError, TypeError
          raise ValidationError, "Cannot read #{value.inspect} as a whole number"
        end

        # Canonicalises a value bound for an `xsd:token` element.
        #
        # Two things happen here, and both are the §8.2b rule — *the model stores the
        # document's representation, not the caller's input*:
        #
        # **`#to_s`.** `TZnakowy` and friends are string types, so an ERP passing `number: 123`
        # or `vat_rate: 23` describes the same document as one passing `"123"` / `"23"`. Left
        # raw, the two produced unequal invoices and DESIGN.md §7.6's round-trip law failed on
        # a field whose value never changed.
        #
        # **Whitespace collapse.** `xsd:token` has `whiteSpace="collapse"`, so the schema sees
        # — and KSeF stores — the collapsed value. {FieldChecks} already measured lengths
        # against the collapsed form; the *consumers* did not, so `vat_rate: " 23 "` passed
        # tier 1 and then made `VatRate.bucket`'s exact lookup raise, and a schema-valid
        # `<P_12> 23 </P_12>` parsed into an invoice that could not be re-serialised at all.
        #
        # Text that is tagged UTF-8 and is not passes through **untouched**: `gsub` and `strip`
        # raise `Encoding::CompatibilityError` on such a value, which is outside this gem's
        # hierarchy, and {FieldChecks#encoding_issue} is what reports it. Canonicalising is not
        # the place to refuse it — `Invoice#errors` is documented to answer rather than raise.
        def text(value)
          return nil if value.nil?

          string = value.to_s
          return string unless string.valid_encoding?

          string.gsub(FieldChecks::COLLAPSE, " ").strip
        end

        # @raise [Ksef::ValidationError] Float is forbidden in any monetary path
        #   (DESIGN.md §4.4) — binary floating point cannot represent 0.01 exactly, and
        #   a rounding error in a tax document is a real problem.
        def decimal(value)
          converted =
            case value
            when BigDecimal then value
            # `BigDecimal("")` and `BigDecimal("abc")` raise a bare ArgumentError, which is not
            # part of this gem's hierarchy. Empty and malformed numeric text is exactly what a
            # rejected document contains, so it must arrive as a ValidationError.
            when Integer, String then strict_decimal(value)
            # A Rational needs an explicit precision. `RATIONAL_PRECISION` is *significant
            # digits*, not decimal places — passing AMOUNT_SCALE + 10 silently truncated large
            # amounts (12345678901234.56 became 12345678901200.0), which is the same class of
            # silent rounding the Float ban exists to prevent.
            when Rational then BigDecimal(value, RATIONAL_PRECISION)
            when Float
              raise ValidationError,
                    "Float is not allowed for monetary or quantity values (got #{value.inspect}). " \
                    "Use a BigDecimal, an Integer, or a decimal String."
            else
              raise ValidationError, "Cannot convert #{value.class} to a decimal: #{value.inspect}"
            end

          # **Negative zero is collapsed to zero**, and that is a `#hash` fix rather than a
          # cosmetic one. `BigDecimal("-0.00") == BigDecimal("0.00")` is true while their
          # hashes differ, so a line whose net came out of an ERP as `"-0.00"` — a routine
          # printf artifact on a zero-delta correction row — compared equal to its positive
          # twin and yet failed as a Hash key. That breaks the `==`/`hash` contract in exactly
          # the way {Issue} documents avoiding. The two are the same amount of money, so the
          # model keeps one representation of it.
          converted.zero? ? BigDecimal(0) : converted
        end

        private

        def utc_string(value)
          value.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        rescue NoMethodError
          raise ValidationError,
                "Cannot read #{value.inspect} as a timestamp; pass a Time, DateTime, Date or " \
                "an ISO-8601 String"
        end

        def strict_decimal(value)
          BigDecimal(value)
        rescue ArgumentError, TypeError
          raise ValidationError, "Cannot read #{value.inspect} as a decimal number"
        end
      end
    end
  end
end
