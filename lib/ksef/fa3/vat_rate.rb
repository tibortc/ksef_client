# frozen_string_literal: true

module Ksef
  module FA3
    # Maps a `TStawkaPodatku` rate code to its numeric percentage and its summary bucket.
    #
    # The bucket mapping is read from the XSD's own documentation and recorded in
    # docs/REFERENCE.md §8.1a. It is not guessable: bucket 4 is the passenger-taxi flat
    # rate and bucket 5 a special procedure, so the buckets are not simply "rates in
    # descending order".
    module VatRate
      # Rate code => [net element, tax element or nil]
      #
      # The zero-rated and exempt buckets have **no** tax element. There is no amount to
      # report and the schema provides nowhere to put one, so a summary must not invent a
      # paired field for them.
      #
      # **Buckets pair a current rate with the historical one it replaced** — 23/22, 8/7, and
      # 4/3. Until 2026-08-24 code `"3"` was mapped to bucket *five*, which is not a rate
      # bucket at all: `P_13_5` is the special procedure of "dział XII rozdział 6a" and
      # `P_14_5` is **"kwota podatku od wartości dodanej"** — foreign VAT under OSS, whose
      # per-line rate lives in `P_12_XII` (a percentage) and not in `P_12` at all. A domestic
      # 3% sale was therefore declared as OSS foreign VAT, on a document the XSD accepts.
      # Found by comparing against `ksef-pdf-generator`, whose summary labels bucket 4
      # "4% lub 3%" and bucket 5 "OSS" (docs/REFERENCE.md §8.1a).
      #
      # **No `P_12` code maps to bucket 5**, and that is correct rather than an omission.
      BUCKETS = {
        "23" => %w[P_13_1 P_14_1],
        "22" => %w[P_13_1 P_14_1],
        "8" => %w[P_13_2 P_14_2],
        "7" => %w[P_13_2 P_14_2],
        "5" => %w[P_13_3 P_14_3],
        "4" => %w[P_13_4 P_14_4],
        "3" => %w[P_13_4 P_14_4],
        "0 KR" => ["P_13_6_1", nil],
        "0 WDT" => ["P_13_6_2", nil],
        "0 EX" => ["P_13_6_3", nil],
        "zw" => ["P_13_7", nil],
        "np I" => ["P_13_8", nil],
        "np II" => ["P_13_8", nil],
        "oo" => ["P_13_10", nil]
      }.freeze

      # Only the codes that denote an actual percentage. The rest are procedures, not
      # rates, and carry no tax.
      PERCENTAGES = { "23" => 23, "22" => 22, "8" => 8, "7" => 7, "5" => 5, "4" => 4, "3" => 3 }.freeze

      class << self
        # @return [Integer, nil] nil for a non-numeric code such as "zw" or "oo"
        def percentage(code) = PERCENTAGES[code.to_s]

        # @return [Array(String, String officially nil)] the net and tax element names
        # @raise [Ksef::ValidationError] for a code the schema does not define
        def bucket(code)
          BUCKETS.fetch(code.to_s) do
            raise ValidationError,
                  "Unknown VAT rate code #{code.inspect}. Permitted: #{BUCKETS.keys.map(&:inspect).join(", ")}"
          end
        end

        # The summary elements no rate code reports into: bucket 5, whose lines carry
        # `P_12_XII` instead. Exposed so the omission is assertable rather than merely
        # commented.
        # @return [Array<String>]
        def unreachable_elements
          %w[P_13_5 P_14_5]
        end

        # Cross-check against the generated enum, so a schema revision that adds or
        # renames a rate code surfaces here rather than in a KSeF rejection.
        # @return [Array<String>] codes in the schema but missing from BUCKETS
        def unmapped_codes
          (Generated::Enums.values_for("TStawkaPodatku") || []) - BUCKETS.keys
        end
      end
    end
  end
end
