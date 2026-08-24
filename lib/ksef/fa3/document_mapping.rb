# frozen_string_literal: true

module Ksef
  module FA3
    # How an {Invoice} becomes the nested, element-name-keyed structure {Serializer} writes.
    #
    # Mixed into {Invoice} and kept apart from it for the same reason {Provenance} is: this is
    # the only part that knows FA(3)'s element names, while the invoice itself is about parties,
    # lines and arithmetic. Ordering is never expressed here — {Serializer} takes it from the
    # generated schema metadata, so this only says *what* the document contains.
    module DocumentMapping
      def to_fa3
        {
          "Naglowek" => header,
          "Podmiot1" => seller.to_fa3(role: :seller),
          "Podmiot2" => buyer.to_fa3(role: :buyer),
          "Fa" => invoice_body
        }
      end

      private

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
          **summary,
          "Adnotacje" => annotations,
          "RodzajFaktury" => invoice_type,
          **(correction ? correction.to_fa3 : {}),
          "FaWiersz" => rows
        }
      end

      # A stated summary wins over a computed one, and for a correction it is the only one
      # there is: its buckets are deltas that its rows need not determine (§8.4).
      def summary
        return totals.to_fa3 if totals

        { **rate_summaries, "P_15" => Formatting.amount(gross_total) }
      end

      # `index + 1` is the *default* number, used unless the line states one of its own —
      # which only a correction's paired before/after rows do (see {Line#initialize}).
      def rows
        lines.each_with_index.map { |line, index| line.to_fa3(row_number: index + 1) }
      end

      # Emitted in schema order by the serializer, so this only has to say which buckets
      # carry a value.
      #
      # **Accumulates per bucket, and that is the whole point.** Several rate codes share one
      # bucket — `"23"` and `"22"` both report into `P_13_1`/`P_14_1`, `"8"` and `"7"` into
      # bucket 2, `"np I"` and `"np II"` into `P_13_8` (§8.1a). Assigning per rate code
      # instead of summing let the last code win, which understated the tax base by the whole
      # share of every earlier code while `P_15` still carried the correct total: an
      # internally inconsistent invoice that passes the XSD. Found by a review on 2026-08-24,
      # after {RoundingInference#computed} — which had always summed per bucket — disagreed
      # with this method.
      def rate_summaries
        bucket_totals.transform_values { |amount| Formatting.amount(amount) }
      end

      # @return [Hash{String => BigDecimal}] element name => accumulated amount
      def bucket_totals
        vat = vat_by_rate

        net_by_rate.each_with_object({}) do |(code, net), acc|
          net_element, tax_element = VatRate.bucket(code)
          add_to(acc, net_element, net)
          # Zero-rated and exempt buckets have no tax element at all (§8.1a).
          add_to(acc, tax_element, vat[code]) if tax_element
        end
      end

      def add_to(totals, element, amount)
        totals[element] = (totals[element] || BigDecimal(0)) + amount
      end
    end
  end
end
