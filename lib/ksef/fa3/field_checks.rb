# frozen_string_literal: true

module Ksef
  module FA3
    # Checks on a single field value: is it readable, is it the right shape, is it one of the
    # values the schema allows.
    #
    # Split out of {ModelValidator} because none of it knows what an invoice is — it knows what
    # `xsd:token` means and what the generated enum tables contain. {ModelValidator} decides
    # *which* fields to check and what to call them; this decides what "too long" and "not one
    # of the permitted values" actually mean.
    #
    # ## The two subtleties worth reading before changing anything here
    #
    # **`xsd:token` collapses whitespace before its facets apply.** `TZnakowy` and `TZnakowy512`
    # both derive from it, so the schema measures — and compares — the *collapsed* value.
    # Measuring the raw string made tier 1 stricter than the schema, which on the send path
    # means refusing documents KSeF admits: upstream's own `ksef-pdf-generator/invoice.xml` has
    # thirteen line names of 577 raw characters that collapse to 500 (2026-08-24).
    #
    # **Text can be tagged UTF-8 and not be UTF-8.** CLAUDE.md warns the ambient locale is not
    # UTF-8, and `docs/REFERENCE.md` §15.1 argues mis-encoded text is the *likely* real-world
    # rejection. `String#strip` raises `Encoding::CompatibilityError` on such a value, out of
    # this gem's hierarchy entirely — so encoding is checked before anything reads the string.
    module FieldChecks
      # `TZnakowy` and `TZnakowy512`: both `minLength="1"`, differing only in the ceiling. A
      # value that is present but empty is a schema violation, not an absent value. They live
      # here rather than on {ModelValidator} because every module that measures a field
      # includes this one.
      SHORT_TEXT = 256
      LONG_TEXT = 512

      # `IDNabywcy` restricts `TZnakowy50` further, to 32.
      BUYER_ID_TEXT = 32

      # `xsd:token`'s `whiteSpace="collapse"`.
      COLLAPSE = /\s+/

      # Outside XML 1.0's `Char` production: the C0 controls except tab, newline and carriage
      # return, plus the two plane-0 noncharacters. Not the *discouraged* characters of §15.1 —
      # {DocumentValidator} handles those — but characters no XML document may contain at all.
      #
      # What happens without this check varies by character, which is worth knowing before
      # anyone tests the guard with the wrong one. Measured through `#to_xml`: **U+0000 alone**
      # raises a bare `ArgumentError: string contains null byte` from inside the serializer.
      # The rest — U+0001, U+0008, U+001F, U+FFFE, U+FFFF — are written out raw, producing a
      # document only tier 2 rejects (`PCDATA invalid Char value 1`). U+000B and U+000C never
      # arrive: Ruby's `\s` covers them, so {Formatting.text}'s collapse has already eaten
      # them. The check earns its place either way — it is what stops non-well-formed output —
      # but only NUL escapes this gem's error hierarchy.
      FORBIDDEN_IN_XML = /[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]/

      private

      # Trim, then squeeze internal whitespace runs to one space: the value the schema sees.
      def collapse(value) = value.to_s.gsub(COLLAPSE, " ").strip

      def encoding_issue(value, field)
        return nil if value.nil? || value.to_s.valid_encoding?

        Issue.new(field: field,
                  message: "contains bytes that are not valid UTF-8; KSeF requires UTF-8 " \
                           "(docs/REFERENCE.md §15.1)")
      end

      def text_errors(value, field, limit, required: false)
        return required ? [Issue.new(field: field, message: "is required")] : [] if value.nil?

        bad_encoding = encoding_issue(value, field)
        return [bad_encoding] if bad_encoding

        text = collapse(value)
        return [Issue.new(field: field, message: "must not be empty")] if text.empty?

        [forbidden_character_issue(text, field), length_issue(text, field, limit)].compact
      end

      def length_issue(text, field, limit)
        return nil if text.length <= limit

        Issue.new(field: field, message: "is #{text.length} characters; the schema allows #{limit}")
      end

      def forbidden_character_issue(text, field)
        offending = text.each_char.find { |char| FORBIDDEN_IN_XML.match?(char) }
        return nil if offending.nil?

        Issue.new(field: field,
                  message: format("contains U+%04X, which XML 1.0 does not permit at all", offending.ord))
      end

      # Membership is read from the generated metadata, so a schema revision that adds or
      # renames a code is picked up by regenerating rather than by editing a list here.
      def enum_issue(field, type, value)
        return Issue.new(field: field, message: "is required") if value.nil?

        # Reported, not skipped: an unreadable value is a problem, and `collapse` would raise on
        # it a line later.
        bad_encoding = encoding_issue(value, field)
        return bad_encoding if bad_encoding

        return nil if Generated::Enums.valid?(type, collapse(value))

        Issue.new(field: field, message: "#{value.inspect} is not one of #{type}'s permitted values")
      end
    end
  end
end
