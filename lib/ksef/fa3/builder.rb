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
      SUBJECT_KEYS = %i[nip name address local_government_unit vat_group_member buyer_id].freeze
      ADDRESS_KEYS = %i[line1 line2 country street city postal_code].freeze
      LINE_KEYS = %i[name quantity unit net_unit_price vat_rate net_amount row_number state_before].freeze
      CORRECTION_KEYS = %i[reason effect period corrected_number previous_seller previous_buyers].freeze
      CORRECTED_KEYS = %i[number issue_date ksef_number].freeze

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

      # Appends a line. Call once per line; row numbers are assigned on serialisation unless
      # a line states its own.
      #
      # @param attributes [Hash] `:name`, `:quantity` (or `:qty`), `:unit`,
      #   `:net_unit_price`, `:vat_rate` (or `:vat`), and optionally `:net_amount`,
      #   `:row_number`, `:state_before`
      def line(**attributes)
        @lines << Line.new(**normalise(attributes, LINE_KEYS, LINE_ALIASES, "line"))
      end

      # Makes this a correction. Optional next to {#corrects}, which is what a correction
      # actually needs; call this for the reason, the effect date and the rest.
      #
      # @param attributes [Hash] `:reason`, `:effect`, `:period`, `:corrected_number`,
      #   `:previous_seller`, `:previous_buyers` — see {Correction}
      def correction(**attributes)
        @correction = normalise(attributes, CORRECTION_KEYS, {}, "correction")
      end

      # Names one invoice this correction corrects. Call once per corrected invoice; a
      # collective correction under art. 106j ust. 3 names many.
      #
      # @param attributes [Hash] `:number`, `:issue_date`, and `:ksef_number` unless the
      #   corrected invoice was issued outside KSeF
      def corrects(**attributes)
        @corrected << CorrectedInvoice.new(**normalise(attributes, CORRECTED_KEYS, {}, "corrects"))
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
        net.each { |code, amount| accumulate(buckets, VatRate.bucket(code).first, amount) }
        vat.each { |code, amount| accumulate(buckets, tax_element(code), amount) }
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

        Invoice.new(**@fields, lines: @lines, correction: assembled_correction)
      end

      private

      # Assembled at the end rather than as {#correction} is called, because a correction is
      # only well-formed once it names a corrected invoice — and the DSL takes those one at a
      # time. Present whenever either half was used, so `corrects` alone is enough and
      # `correction` alone fails with {Correction::NAMES_NOTHING} rather than silently
      # producing an invoice that is not a correction.
      def assembled_correction
        return nil if @correction.nil? && @corrected.empty?

        Correction.new(**(@correction || {}), corrected: @corrected)
      end

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

      def subject(attributes, role:)
        normalised = normalise(attributes, SUBJECT_KEYS, {}, "#{role} subject")
        require_keys(normalised, %i[nip name address], role)
        # `normalise` returns a fresh Hash, so replacing the address in place is safe —
        # and reads better than relying on splat-then-override precedence.
        normalised[:address] = coerce_address(normalised[:address], role)
        Subject.new(**normalised)
      end

      # Accepts an {Address}, a Hash of its attributes, or a pre-formatted string — the
      # last because FA(3) models an address as free-text lines anyway (see {Address}).
      def coerce_address(value, role)
        case value
        when Address then value
        when String then Address.new(line1: value)
        when Hash
          Address.new(**normalise(value.transform_keys(&:to_sym), ADDRESS_KEYS, {}, "#{role} address"))
        else
          raise ValidationError,
                "#{role} address must be a Ksef::FA3::Address, a Hash of its fields, or a formatted " \
                "String; got #{value.class}"
        end
      end

      # Translates shorthand, then rejects anything the target object does not accept.
      def normalise(attributes, permitted, aliases, what)
        aliases.each do |short, long|
          next unless attributes.key?(short) && attributes.key?(long)

          raise ValidationError, "Pass either #{short}: or #{long}: to #{what}, not both"
        end

        translated = attributes.to_h { |key, value| [aliases.fetch(key, key), value] }
        unknown = translated.keys - permitted
        raise ValidationError, unknown_message(unknown, permitted, aliases, what) unless unknown.empty?

        translated
      end

      def unknown_message(unknown, permitted, aliases, what)
        message = "Unknown #{what} option(s) #{unknown.map(&:inspect).join(", ")}. " \
                  "Permitted: #{permitted.join(", ")}"
        return message if aliases.empty?

        "#{message}. Shorthand: #{aliases.map { |short, long| "#{short} for #{long}" }.join(", ")}"
      end

      def require_keys(attributes, keys, what)
        missing = keys.reject { |key| attributes.key?(key) }
        return if missing.empty?

        raise ValidationError, "Incomplete #{what}, missing #{missing.join(", ")}"
      end
    end
  end
end
