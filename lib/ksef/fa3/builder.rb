# frozen_string_literal: true

module Ksef
  module FA3
    # The object yielded by {Ksef::FA3.build}. Collects fields, then hands them to
    # {Invoice} — which keeps every computation and every schema default in one place
    # rather than splitting them between the model and the DSL.
    #
    # Two deliberate choices about strictness. An unknown or misspelled key **raises**,
    # listing what is permitted, because the alternative is a silently incomplete invoice
    # — the same reasoning as {Serializer}'s treatment of unknown element names. But a
    # single-value field set twice simply takes the later value, which is what anyone
    # writing a builder expects, and what `f.number` called twice obviously ought to do.
    class Builder
      # The type-specific halves of the DSL, each with its own assembly (§8.4, §8.5).
      include Corrections
      include Advances
      include Subjects

      SUBJECT_KEYS = %i[nip name address local_government_unit vat_group_member buyer_id].freeze
      ADDRESS_KEYS = %i[line1 line2 country street city postal_code].freeze
      LINE_KEYS = %i[name quantity unit net_unit_price vat_rate net_amount row_number state_before].freeze
      CORRECTION_KEYS = %i[reason effect period corrected_number previous_seller previous_buyers
                           paid_before exchange_rate_before].freeze
      CORRECTED_KEYS = %i[number issue_date ksef_number].freeze
      ORDER_KEYS = %i[total].freeze
      ORDER_LINE_KEYS = %i[name quantity unit net_unit_price net_amount vat_amount vat_rate
                           row_number state_before].freeze
      ADVANCE_KEYS = %i[ksef_number number].freeze

      # English shorthand from DESIGN.md §8's example. The canonical names work too, so
      # `qty:` and `quantity:` are interchangeable — but passing both is an error rather
      # than a silent last-one-wins.
      LINE_ALIASES = { qty: :quantity, vat: :vat_rate }.freeze

      # Reported together, so one round trip tells the caller everything that is missing.
      REQUIRED = %i[seller buyer number issue_date].freeze

      def initialize
        @fields = {}
        @lines = []
        @corrected = []
        @correction = nil
        @order = nil
        @order_lines = []
        @advances = []
      end

      # @param attributes [Hash] `:nip`, `:name`, `:address`, and optionally
      #   `:local_government_unit` / `:vat_group_member`
      def seller(**attributes) = @fields[:seller] = subject(attributes, role: :seller)

      # @see #seller
      def buyer(**attributes) = @fields[:buyer] = subject(attributes, role: :buyer)

      # @param value [String] the invoice number (`P_2`)
      def number(value) = @fields[:number] = value

      # @param value [Date, String] date of issue (`P_1`)
      def issue_date(value) = @fields[:issue_date] = value

      # @param value [String] ISO-4217 code; defaults to `"PLN"`
      def currency(value) = @fields[:currency] = value

      # @param value [Time, DateTime, Date, String] document generation timestamp;
      #   defaults to the moment of serialisation
      def issued_at(value) = @fields[:issued_at] = value

      # Polish VAT law permits both strategies and they can differ by a grosz, so this is
      # explicit rather than inferred (DESIGN.md §7.3).
      # @param value [Symbol] `:per_line` (default) or `:per_summary`
      def rounding(value) = @fields[:rounding] = value

      # @param value [String] a `TRodzajFaktury` code; defaults to `"VAT"`
      def invoice_type(value) = @fields[:invoice_type] = value

      # The invoice attachment (`Zalacznik`), a sibling of `Fa` carrying no amounts.
      #
      # Takes an {Attachment}, or the blocks to make one from — the one-block case is the
      # common one and does not deserve two levels of ceremony:
      #
      #     f.attachment Ksef::FA3::DataBlock.new(metadata: { "Kod PPE" => "999" })
      #
      # @param value [Attachment, DataBlock, Array<DataBlock>]
      def attachment(value) = @fields[:attachment] = Attachment.wrap(value)

      # Appends a line. Call once per line; row numbers are assigned on serialisation unless
      # a line states its own.
      #
      # @param attributes [Hash] `:name`, `:quantity` (or `:qty`), `:unit`,
      #   `:net_unit_price`, `:vat_rate` (or `:vat`), and optionally `:net_amount`,
      #   `:row_number`, `:state_before`
      def line(**attributes)
        @lines << Line.new(**normalise(attributes, LINE_KEYS, LINE_ALIASES, "line"))
      end

      # States the tax summary instead of having it computed from the lines — which a
      # correction must do, its buckets being deltas its rows need not determine
      # (docs/REFERENCE.md §8.4).
      #
      # Keyed by **rate code**, as {#line} is, and mapped to summary buckets here. The model
      # stores the buckets, because that mapping is not invertible: `"23"` and `"22"` share
      # one (§8.1a).
      #
      # @param gross [BigDecimal, Integer, String] `P_15`
      # @param net [Hash{String => Object}] rate code => net amount
      # @param vat [Hash{String => Object}] rate code => tax amount
      def totals(gross:, net: {}, vat: {})
        buckets = {}
        # `nil` reads as "no buckets of this kind", which is what a caller who has only one
        # side of the summary naturally passes. Left alone it raised a bare NoMethodError.
        (net || {}).each { |code, amount| accumulate(buckets, VatRate.bucket(code).first, amount) }
        (vat || {}).each { |code, amount| accumulate(buckets, tax_element(code), amount) }
        @fields[:totals] = Totals.new(buckets: buckets, gross: gross)
      end

      # @return [Invoice]
      # @raise [Ksef::ValidationError] if a required field was never set
      def to_invoice
        missing = REQUIRED.reject { |key| @fields.key?(key) }
        unless missing.empty?
          raise ValidationError,
                "Incomplete invoice, missing #{missing.join(", ")}. " \
                "Every invoice needs a seller, a buyer, a number and an issue date."
        end

        Invoice.new(**@fields, lines: @lines, correction: assembled_correction,
                               order: assembled_order, advances: @advances)
      end

      private

      # Several rate codes share a bucket (§8.1a), so a summary accumulates rather than
      # assigning — the shape of a bug an audit found in {DocumentMapping} on 2026-08-24.
      def accumulate(buckets, element, amount)
        buckets[element] = Formatting.decimal(buckets.fetch(element, 0)) + Formatting.decimal(amount)
      end

      # The zero-rated and exempt buckets have no tax element at all: there is no amount to
      # report and nowhere in the schema to put one (§8.1a).
      def tax_element(code)
        VatRate.bucket(code).last ||
          raise(ValidationError,
                "Rate code #{code.inspect} has no tax bucket — it is zero-rated, exempt or " \
                "reverse-charged, so there is no VAT amount to state. Pass it under net: only.")
      end
    end
  end
end
