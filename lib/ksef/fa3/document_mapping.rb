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

      # The summary buckets as the document will carry them: element name => amount, rounded
      # to the two places `TKwotowy` allows. A stated summary answers with what it states; a
      # derived one with what it derives, rounded per bucket exactly as `#to_xml` rounds it.
      #
      # Public because tier 3 reconciles against it ({BusinessValidator}) and reaching for it
      # through `send` would have made a private method load-bearing from outside.
      #
      # @return [Hash{String => BigDecimal}]
      def summary_buckets
        return totals.buckets if totals

        bucket_totals.transform_values { |amount| amount.round(Formatting::AMOUNT_SCALE) }
      end

      private

      # The one element in FA(3) that declares **fixed** attributes — `Kol` declares `@Typ`,
      # which is required but not fixed — and they are declared on `KodFormularza` itself, on
      # the `xsd:extension` inside its anonymous simpleContent type, keyed
      # "TNaglowek/KodFormularza".
      #
      # This read `Generated::Types["TNaglowek"]` until 2026-08-26, and got the right answer
      # from the wrong place: the generator's attribute lookup used a descendant axis, so
      # `TNaglowek` inherited the attributes of everything beneath it and these two surfaced
      # one level too high. Both halves are fixed, and this is the only caller either half
      # had. Nothing about the emitted document changes.
      # Every value here is fixed by the schema except the generation timestamp, and the fixed
      # ones are read from the generated metadata rather than restated.
      def header
        {
          "KodFormularza" => Serializer::Element.new(text: "FA", attributes: fixed_attributes),
          "WariantFormularza" => schema_variant,
          "DataWytworzeniaFa" => issued_at || Formatting.date_time(Time.now)
        }
      end

      # `fetch`, so a renamed key fails by name rather than as `NoMethodError` on nil.
      def fixed_attributes
        declared = Generated::Types::ALL.fetch("TNaglowek/KodFormularza")[:attributes]
        declared.select { |attribute| attribute[:fixed] }
                .to_h { |attribute| [attribute[:name], attribute[:fixed]] }
      end

      # `WariantFormularza` is `xsd:byte` restricted to a single enumerated value, so the schema
      # states it as surely as it states `KodFormularza`'s fixed attributes — and this was a
      # hand-written `3` directly beneath a comment claiming the fixed values are read from the
      # metadata. The codegen dropped element-level enumerations until 2026-08-26, so the
      # comment described an intention rather than the line under it (audit finding).
      #
      # `fetch(0)` rather than `first`: a one-member enumeration that stopped having one member
      # should fail here, not emit nil into the document.
      def schema_variant
        Generated::Types.ordered_elements("TNaglowek")
                        .find { |element| element[:name] == "WariantFormularza" }
                        .fetch(:values).fetch(0)
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
          "FakturaZaliczkowa" => advances.map(&:to_fa3),
          "FaWiersz" => rows,
          "Zamowienie" => order&.to_fa3
          # `compact`, because a nil value is not "absent" to {Serializer}: it writes an empty
          # element for one. An empty Array *is* absent — it repeats zero times.
        }.compact
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
      # bucket 2, `"4"` and `"3"` into bucket 4 (§8.1a). Assigning per rate code
      # instead of summing let the last code win, which understated the tax base by the whole
      # share of every earlier code while `P_15` still carried the correct total: an
      # internally inconsistent invoice that passes the XSD. Found by a review on 2026-08-24,
      # after {RoundingInference.computed} — which had always summed per bucket — disagreed
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
