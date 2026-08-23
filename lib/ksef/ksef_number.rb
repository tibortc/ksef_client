# frozen_string_literal: true

require "date"

module Ksef
  # A KSeF number — the identifier the system assigns to an accepted invoice
  # (docs/REFERENCE.md §13).
  #
  #     9999999999-RRRRMMDD-FFFFFFFFFFFF-FF
  #
  # Seller NIP (10) · acceptance date `YYYYMMDD` (8) · a 12-character technical part ·
  # a two-character CRC-8 checksum. Always **exactly 35 characters**.
  #
  # ## Why the date matters more than it looks
  #
  # Per `limity/limity-api.md`, **the invoice's official receipt date is the date its KSeF
  # number was assigned** — not the date a client downloaded it, and not the invoice's own
  # issue date. That makes {#assigned_on} a legally meaningful field rather than metadata,
  # which is why it is parsed into a `Date` rather than left as eight characters.
  #
  # ## Why parse at all, rather than pass the string through
  #
  # The checksum is the point. KSeF numbers get copied between systems, typed into
  # spreadsheets and read down telephones, and a CRC-8 catches exactly the transpositions
  # and single-character slips that happen on the way. Checking it locally turns a silent
  # lookup failure into an immediate, specific error.
  KsefNumber = Data.define(:value, :nip, :assigned_on, :technical, :checksum)

  # Reopened rather than using a `Data.define` block so the constants land on the class.
  class KsefNumber
    LENGTH = 35

    # Uppercase hex only, in both the technical part and the checksum.
    FORMAT = /\A(\d{10})-(\d{8})-([0-9A-F]{12})-([0-9A-F]{2})\z/

    # CRC-8 with polynomial `0x07`, initial value `0x00`, no input or output reflection and
    # no final XOR — computed over the **first 32 characters**, i.e. everything before the
    # final hyphen (§13). Verified against the Ministry's own documented example, which
    # doubles as this implementation's golden vector.
    POLYNOMIAL = 0x07
    CHECKSUM_INPUT_LENGTH = 32

    class << self
      # @param value [String]
      # @return [KsefNumber]
      # @raise [Ksef::ValidationError] on a malformed number, an impossible date, or a
      #   checksum mismatch
      def parse(value)
        text = value.to_s
        match = FORMAT.match(text) or raise ValidationError, malformed(text)
        nip, date, technical, checksum = match.captures

        verify_checksum!(text, checksum)
        new(
          value: text,
          nip: nip,
          assigned_on: parse_date(date, text),
          technical: technical,
          checksum: checksum
        )
      end

      # @return [Boolean] true when {parse} would succeed
      def valid?(value)
        parse(value)
        true
      rescue ValidationError
        false
      end

      # @param text [String] the characters to run the CRC over
      # @return [Integer] 0..255
      def crc8(text)
        text.each_byte.reduce(0) do |crc, byte|
          register = crc ^ byte
          8.times do
            register = if register.nobits?(0x80)
                         (register << 1) & 0xFF
                       else
                         ((register << 1) ^ POLYNOMIAL) & 0xFF
                       end
          end
          register
        end
      end

      # The checksum a given number *should* carry, as the two uppercase hex characters the
      # format uses.
      #
      # @param text [String] a full KSeF number, or just its first 32 characters
      # @return [String]
      def checksum_for(text)
        format("%02X", crc8(text.to_s[0, CHECKSUM_INPUT_LENGTH]))
      end

      private

      def verify_checksum!(text, checksum)
        expected = checksum_for(text)
        return if expected == checksum

        raise ValidationError,
              "KSeF number #{text.inspect} has checksum #{checksum}, but its first " \
              "#{CHECKSUM_INPUT_LENGTH} characters give #{expected}. A CRC-8 mismatch usually " \
              "means the number was mistyped or truncated in transit (docs/REFERENCE.md §13)."
      end

      def parse_date(digits, text)
        Date.strptime(digits, "%Y%m%d")
      rescue Date::Error
        raise ValidationError,
              "KSeF number #{text.inspect} carries #{digits.inspect} where an acceptance date " \
              "YYYYMMDD belongs, and that is not a real date."
      end

      def malformed(text)
        "KSeF number #{text.inspect} is malformed (#{text.length} characters, expected #{LENGTH}). " \
          "The form is NIP-YYYYMMDD-<12 uppercase hex>-<2 uppercase hex>, " \
          "e.g. 5265877635-20250826-0100001AF629-AF."
      end
    end

    # The date KSeF accepted the invoice, which is its **official receipt date** — not the
    # date it was downloaded, and not the invoice's own issue date.
    def to_s = value

    # Convenience for the common case of holding a number only to look an invoice up.
    def to_str = value
  end
end
