# frozen_string_literal: true

module Ksef
  module FA3
    # What makes a `KOR` a correction rather than an invoice: why it was issued, when it
    # takes effect, and which invoices it corrects.
    #
    # In the schema these are an anonymous `<xsd:sequence minOccurs="0">` sitting between
    # `RodzajFaktury` and `ZaliczkaCzesciowa`. The group is optional; **`DaneFaKorygowanej`
    # is not optional within it**, which is why {#initialize} refuses a correction that names
    # no corrected invoice. A `KOR` carrying `PrzyczynaKorekty` and nothing else is a
    # document the XSD rejects, and the useful moment to say so is at construction.
    #
    # ## What it does not carry
    #
    # `P_15ZK` and `KursWalutyZK` — the amount paid before correction — live in the same
    # group and are **not** modelled. Their documentation scopes them to *"korekt faktur
    # zaliczkowych"* and art. 106f ust. 3, i.e. `KOR_ZAL` and `KOR_ROZ`, which are separate
    # invoice types and later work (DESIGN.md §7.4). A document carrying them parses; they
    # surface through {Invoice#unmapped_elements}, because they are whole elements and that
    # is precisely the loss a path diagnostic can see.
    Correction = Data.define(
      :reason, :effect, :corrected, :period, :corrected_number, :previous_seller, :previous_buyers
    )

    # Construction, canonicalisation and serialisation for {Ksef::FA3::Correction}.
    class Correction
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      # The `RodzajFaktury` values these elements belong to — **stated by the XSD itself**, in
      # the annotation on the anonymous sequence that holds them: *"Dane dla przypadków, gdy
      # pole RodzajFaktury przyjmuje wartości KOR, KOR_ZAL lub KOR_ROZ"*.
      #
      # What the schema cannot do is *enforce* it: the group sits in the same sequence whatever
      # the type, so a `VAT` invoice carrying `DaneFaKorygowanej` validates clean. That gap is
      # tier 1's, and {ModelValidator} fills it (docs/REFERENCE.md §8.4).
      CORRECTING_TYPES = %w[KOR KOR_ZAL KOR_ROZ].freeze

      NAMES_NOTHING = "A correction must name at least one corrected invoice. " \
                      "`DaneFaKorygowanej` is mandatory once any correction element is " \
                      "present, so a correction without one cannot be serialised."

      # @param corrected [CorrectedInvoice, Array<CorrectedInvoice>] `DaneFaKorygowanej`, at
      #   least one
      # @param reason [String, nil] `PrzyczynaKorekty` — why the correction was issued
      # @param effect [Integer, String, nil] `TypKorekty`, when the correction takes effect
      #   in the VAT register: `1` at the date the corrected invoice was recorded, `2` at the
      #   date this correction was issued, `3` at some other date — including the case where
      #   different rows take effect on different dates
      # @param period [String, nil] `OkresFaKorygowanej` — the period a collective discount
      #   under art. 106j ust. 3 relates to
      # @param corrected_number [String, nil] `NrFaKorygowany` — the *right* number, for the
      #   case where the thing being corrected is the corrected invoice's own number. The
      #   wrong one stays in `NrFaKorygowanej`, so the pair reads "this, not that"
      # @param previous_seller [Subject, nil] `Podmiot1K` — the seller as the corrected
      #   invoice stated them
      # @param previous_buyers [Subject, Array<Subject>] `Podmiot2K` — the buyer, and any
      #   additional buyers, as the corrected invoice stated them
      # @raise [Ksef::ValidationError] if no corrected invoice is named
      def initialize(corrected:, reason: nil, effect: nil, period: nil, corrected_number: nil,
                     previous_seller: nil, previous_buyers: [])
        entries = self.class.wrap(corrected)
        raise ValidationError, NAMES_NOTHING if entries.empty?

        super(
          previous_seller: previous_seller,
          reason: Formatting.text(reason),
          period: Formatting.text(period),
          corrected_number: Formatting.text(corrected_number),
          # `dup` before freezing: `Array(x)` returns `x` itself when it is already an Array,
          # so freezing in place froze the *caller's* array and made their next `<<` raise.
          corrected: entries.dup.freeze,
          previous_buyers: self.class.wrap(previous_buyers).dup.freeze,
          # `TypKorekty` restricts `xsd:integer`, whose value space is integers — so `"03"`
          # and `3` denote the same thing and the model stores the value, not the lexical
          # form (§8.2b). Contrast {Line#vat_rate}, a token whose value space *is* strings.
          effect: effect.nil? ? nil : Formatting.integer(effect)
        )
      end

      # `Array()` is not usable here: it splats a Hash into an array of pairs, so
      # `Correction.new(corrected: { number: ..., issue_date: ... })` — a natural mistake —
      # was accepted and then made `#to_xml` raise `NoMethodError` on an Array.
      def self.wrap(value)
        return [] if value.nil?

        value.is_a?(Array) ? value : [value]
      end

      def to_fa3
        {
          "PrzyczynaKorekty" => reason,
          "TypKorekty" => effect&.to_s,
          "DaneFaKorygowanej" => corrected.map(&:to_fa3),
          "OkresFaKorygowanej" => period,
          "NrFaKorygowany" => corrected_number,
          "Podmiot1K" => previous_seller&.to_fa3(role: :previous_seller),
          "Podmiot2K" => previous_buyers.map { |subject| subject.to_fa3(role: :previous_buyer) }
        }.compact
      end
    end
  end
end
