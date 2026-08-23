# frozen_string_literal: true

module Ksef
  module FA3
    # A complete FA(3) invoice.
    #
    # Phase 1 covers the plain `VAT` type. The remaining six types (DESIGN.md §7.4) reuse
    # this core and add their own required and forbidden fields.
    Invoice = Data.define(
      :seller, :buyer, :number, :issue_date, :lines,
      :currency, :issued_at, :rounding, :invoice_type, :raw_document
    )

    # Computation, defaults and serialisation for {Ksef::FA3::Invoice}.
    class Invoice
      # Both strategies are permitted by Polish VAT law, and silently choosing one creates
      # one-grosz mismatches against a user's ERP (DESIGN.md §7.3).
      ROUNDING_STRATEGIES = %i[per_line per_summary].freeze

      # All five flags plus the three wrapper elements are mandatory (§8.2), and every one of
      # them is the same on an ordinary domestic invoice. Defaulting them to "not applicable"
      # is what makes such an invoice possible without the caller knowing any of this — and
      # they are fixed, so this is a constant rather than a method that rebuilds it per call.
      ANNOTATIONS = {
        "P_16" => Formatting.flag(false),
        "P_17" => Formatting.flag(false),
        "P_18" => Formatting.flag(false),
        "P_18A" => Formatting.flag(false),
        "Zwolnienie" => { "P_19N" => "1" },
        "NoweSrodkiTransportu" => { "P_22N" => "1" },
        "P_23" => Formatting.flag(false),
        "PMarzy" => { "P_PMarzyN" => "1" }
      }.freeze

      # Everything except {#raw_document}: the fields that make this invoice *this* invoice.
      # {Provenance} reads this to decide what equality, hashing and `#inspect` cover.
      IDENTITY = (members - [:raw_document]).freeze

      # Equality, `#inspect` and {Provenance#unmapped_elements} — everything to do with the
      # document this invoice may have been read from.
      include Provenance

      # `issued_at` is normalised to the string the document will carry, which is the same
      # rule {Address} and {Line} follow: **the model stores the document's representation,
      # not the caller's input.** A `Time` renders to `"2026-08-22T10:00:00Z"` here rather
      # than at serialisation, so an invoice built from a Time and the same invoice parsed
      # back from XML are one object — the round-trip law of DESIGN.md §7.6 would otherwise
      # fail on a field whose value never actually changed.
      #
      # `nil` is left alone, and means something different: not "no timestamp" but "stamp it
      # when you serialise". Such an invoice is not fully determined and cannot round-trip
      # to an equal object, which is a property of that choice rather than a defect.
      def initialize(seller:, buyer:, number:, issue_date:, lines:,
                     currency: "PLN", issued_at: nil, rounding: :per_line, invoice_type: "VAT",
                     raw_document: nil)
        unless ROUNDING_STRATEGIES.include?(rounding)
          raise ValidationError,
                "Unknown rounding strategy #{rounding.inspect}; expected one of #{ROUNDING_STRATEGIES.inspect}"
        end
        raise ValidationError, "An invoice needs at least one line" if lines.nil? || lines.empty?

        super(
          seller: seller, buyer: buyer, number: number, issue_date: issue_date, lines: lines,
          currency: currency, rounding: rounding, invoice_type: invoice_type,
          raw_document: raw_document,
          issued_at: issued_at.nil? ? nil : Formatting.date_time(issued_at)
        )
      end

      # Net totals per rate code, in the order the lines first mention each rate, so the
      # output is stable for a given invoice.
      # @return [Hash{String => BigDecimal}]
      def net_by_rate
        lines.each_with_object({}) do |line, acc|
          code = line.vat_rate.to_s
          acc[code] = (acc[code] || BigDecimal(0)) + line.net
        end
      end

      # @return [Hash{String => BigDecimal}]
      def vat_by_rate
        rounding == :per_line ? vat_rounded_per_line : vat_rounded_per_summary
      end

      def net_total = net_by_rate.values.sum(BigDecimal(0))
      def vat_total = vat_by_rate.values.sum(BigDecimal(0))
      def gross_total = net_total + vat_total

      def to_xml = Serializer.new(to_fa3).to_xml

      # @raise [Ksef::ValidationError] if the document does not conform to the XSD
      def validate! = Validator.validate!(to_xml)
      def valid? = Validator.valid?(to_xml)

      def to_fa3
        {
          "Naglowek" => header,
          "Podmiot1" => seller.to_fa3(role: :seller),
          "Podmiot2" => buyer.to_fa3(role: :buyer),
          "Fa" => invoice_body
        }
      end

      private

      # Round each line, then sum. Matches an ERP that prices line by line.
      def vat_rounded_per_line
        lines.each_with_object({}) do |line, acc|
          code = line.vat_rate.to_s
          acc[code] = (acc[code] || BigDecimal(0)) + line.vat
        end
      end

      # Sum the nets, then round once. Fewer rounding events, so it can differ from
      # :per_line by a grosz — which is exactly why the choice is explicit.
      def vat_rounded_per_summary
        net_by_rate.to_h do |code, net|
          percentage = VatRate.percentage(code)
          rounded = percentage ? (net * percentage / 100).round(Formatting::AMOUNT_SCALE) : BigDecimal(0)
          [code, rounded]
        end
      end

      def header
        # Every value here is fixed by the schema except the generation timestamp, and the
        # fixed ones are read from the generated metadata rather than restated.
        attributes = Generated::Types["TNaglowek"][:attributes]
                     .select { |a| a[:fixed] }
                     .to_h { |a| [a[:name], a[:fixed]] }

        {
          "KodFormularza" => Serializer::Element.new(text: "FA", attributes: attributes),
          "WariantFormularza" => 3,
          "DataWytworzeniaFa" => issued_at || Formatting.date_time(Time.now)
        }
      end

      def invoice_body
        {
          "KodWaluty" => currency,
          "P_1" => Formatting.date(issue_date),
          "P_2" => number,
          **rate_summaries,
          "P_15" => Formatting.amount(gross_total),
          "Adnotacje" => ANNOTATIONS,
          "RodzajFaktury" => invoice_type,
          "FaWiersz" => rows
        }
      end

      def rows
        lines.each_with_index.map { |line, index| line.to_fa3(row_number: index + 1) }
      end

      # Emitted in schema order by the serializer, so this only has to say which buckets
      # carry a value.
      def rate_summaries
        vat = vat_by_rate

        net_by_rate.each_with_object({}) do |(code, net), acc|
          net_element, tax_element = VatRate.bucket(code)
          acc[net_element] = Formatting.amount(net)
          # Zero-rated and exempt buckets have no tax element at all (§8.1a).
          acc[tax_element] = Formatting.amount(vat[code]) if tax_element
        end
      end
    end
  end
end
