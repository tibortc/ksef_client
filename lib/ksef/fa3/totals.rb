# frozen_string_literal: true

module Ksef
  module FA3
    # The tax summary an invoice **states** — `P_13_*`, `P_14_*` and `P_15` — as against the
    # one {Invoice} computes from its lines.
    #
    # ## Why a correction needs this and a plain invoice does not
    #
    # An ordinary `VAT` invoice's summaries are a function of its rows, so recomputing them is
    # safe and {RoundingInference} can even recover *how* they were computed. A `KOR` is not:
    # its buckets carry **deltas**, and FA(3) nowhere requires its rows to determine them.
    # Three of the Ministry's five worked corrections settle it — Przykład 5 and Przykład 6
    # carry no `FaWiersz` at all, and Przykład 7's single row states a name, a CN code and a
    # quantity with no amount anywhere (docs/REFERENCE.md §8.4).
    #
    # So for a correction the summary is *read*, never derived. Deriving one would invent a
    # number the document already has, which is the failure this type exists to prevent.
    #
    # ## Keyed by element name, deliberately
    #
    # {Invoice#net_by_rate} is keyed by rate code, and that mapping is **not invertible**:
    # `"23"` and `"22"` both report into `P_13_1` (§8.1a), so a document stating `P_13_1`
    # alone does not say which rate produced it. Element names are the document's own
    # representation and the only keying that round-trips — the rule {Address} and {Line}
    # already follow (§8.2b).
    Totals = Data.define(:buckets, :gross)

    # Membership, arithmetic and serialisation for {Ksef::FA3::Totals}.
    class Totals
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      # The summary buckets, read from the generated schema metadata rather than restated
      # here (DESIGN.md §7.1). The `W` twins — `P_14_1W` and its siblings — are excluded:
      # they are the PLN equivalents a foreign-currency invoice carries *alongside* a bucket,
      # not buckets of their own, and summing them would double-count the tax.
      ELEMENTS = Generated::Types.ordered_elements("Faktura/Fa")
                                 .map { |particle| particle[:name] }
                                 .grep(/\AP_1[34]_\d/)
                                 .reject { |name| name.end_with?("W") }
                                 .freeze

      # `P_13_*` is a net amount and `P_14_*` the tax on it. That split is what lets
      # {Invoice#net_total} and {Invoice#vat_total} keep answering for a stated summary.
      NET_ELEMENTS = ELEMENTS.grep(/\AP_13_/).freeze
      TAX_ELEMENTS = ELEMENTS.grep(/\AP_14_/).freeze

      # @param gross [BigDecimal, Integer, String] `P_15`, the total amount due
      # @param buckets [Hash{String => BigDecimal, Integer, String}] element name => amount,
      #   for the buckets this invoice states; omitted buckets are simply absent
      # @raise [Ksef::ValidationError] on an element name that is not a summary bucket, or an
      #   amount that is not a decimal — a `Float` included (DESIGN.md §4.4)
      def initialize(gross:, buckets: {})
        # Rounded to the scale `TKwotowy` permits, for the same reason {Line} rounds: the
        # model reports the figure the document will actually carry (§8.2b).
        super(
          buckets: self.class.verified_buckets(buckets),
          gross: Formatting.decimal(gross).round(Formatting::AMOUNT_SCALE)
        )
      end

      # @return [Hash{String => BigDecimal}] frozen, checked for spelling and for collisions
      def self.verified_buckets(buckets)
        unless buckets.respond_to?(:to_h)
          raise ValidationError, "Totals buckets must be a Hash of element name => amount, got #{buckets.inspect}"
        end

        pairs = buckets.to_h.map { |name, amount| [name.to_s, amount] }
        reject_duplicates(pairs.map(&:first))
        reject_unknown(pairs.map(&:first))

        pairs.to_h { |name, amount| [name, Formatting.decimal(amount).round(Formatting::AMOUNT_SCALE)] }
             .freeze
      end

      # @return [BigDecimal] the sum of every `P_13_*` bucket stated
      def net = sum_of(NET_ELEMENTS)

      # @return [BigDecimal] the sum of every `P_14_*` bucket stated
      def vat = sum_of(TAX_ELEMENTS)

      def to_fa3
        buckets.to_h { |name, amount| [name, Formatting.amount(amount)] }
               .merge("P_15" => Formatting.amount(gross))
      end

      private

      def sum_of(elements)
        buckets.sum(BigDecimal(0)) { |name, amount| elements.include?(name) ? amount : BigDecimal(0) }
      end

      # Keys are compared after `#to_s`, so `:P_13_1` and `"P_13_1"` are one bucket — and
      # `Hash#to_h` would silently keep only the last of them, dropping a tax base without a
      # word. {Builder#totals} accumulates colliding *rate codes* on purpose, because several
      # share a bucket (§8.1a); two spellings of one element name are a mistake instead.
      private_class_method def self.reject_duplicates(names)
        repeated = names.tally.select { |_, count| count > 1 }.keys
        return if repeated.empty?

        raise ValidationError,
              "Summary bucket(s) #{repeated.map(&:inspect).join(", ")} given more than once. " \
              "Keys are compared as strings, so :P_13_1 and \"P_13_1\" are the same bucket; " \
              "add the amounts up yourself rather than letting one of them win."
      end

      private_class_method def self.reject_unknown(names)
        unknown = names - ELEMENTS
        return if unknown.empty?

        raise ValidationError,
              "Unknown summary bucket(s) #{unknown.map(&:inspect).join(", ")}. " \
              "Permitted: #{ELEMENTS.join(", ")}. P_15 is passed as gross:, and the `W` twins " \
              "of a foreign-currency invoice are not modelled (docs/REFERENCE.md §8.4)."
      end
    end
  end
end
