# frozen_string_literal: true

module Ksef
  module FA3
    # Works out which rounding strategy produced a document's tax summaries.
    #
    # The strategy is not a field in an FA(3) invoice. It is *how* the summaries were
    # computed, and the two legal ways of computing them — round each line, or round each
    # bucket once — differ by at most a grosz (DESIGN.md §7.3). So it cannot be read, only
    # inferred: whichever strategy reproduces the `P_14_*` values the document carries is
    # the one that made it.
    #
    # Lives apart from {Parser} because it is the one piece of parsing that is not reading.
    # Everything else there maps an element to a field; this reasons backwards from an
    # arithmetic result to the procedure that produced it.
    module RoundingInference
      # The tax-summary elements, taken from {VatRate::BUCKETS} rather than matched by name.
      #
      # A `start_with?("P_14")` scan would also pick up `P_14_1W` and friends — the
      # PLN-equivalent twins that exist for foreign-currency invoices — and those are not
      # what either strategy computes. Deriving the list from the bucket table also means a
      # schema revision cannot leave it stale.
      TAX_ELEMENTS = VatRate::BUCKETS.values.filter_map { |(_net, tax)| tax }.uniq.freeze

      class << self
        # @param invoice [Invoice] parsed with any strategy; only its lines are consulted
        # @param stated [Hash{String => BigDecimal}] the document's own `P_14_*` values
        # @return [Invoice] the invoice, with the strategy that reproduces `stated`
        #
        # `:per_line` wins a tie, and a tie is the common case — the two agree on most
        # invoices. When **neither** matches, the document's summaries reconcile with its own
        # lines under no strategy at all. That is a business-rule violation (tier 3, still
        # unbuilt — docs/REFERENCE.md §15.6), not a parse failure: the document exists and may
        # well be sitting in KSeF, so it is left as `:per_line` and not argued with.
        # **Decided from the lines alone**, so the parser can settle the strategy *before*
        # constructing the invoice rather than constructing one and copying it.
        #
        # That ordering is load-bearing. {Invoice.scaled_gross} drops `stated_gross` when it
        # equals what the rows derive — and "what the rows derive" depends on the strategy. A
        # parser that built with a provisional `:per_line`, let the constructor drop the
        # document's `P_15`, and *then* copied the invoice to `:per_summary` lost the figure
        # for good: the copy re-ran the constructor with `stated_gross` already nil. Przykład 1
        # would have shown it, except every one of the twenty-six pinned samples infers
        # `:per_line`, so the corpus is structurally blind to it (docs/REFERENCE.md §17.2).
        #
        # @param lines [Array<Line>]
        # @param stated [Hash{String => BigDecimal}] the document's own `P_14_*` values
        # @return [Symbol] `:per_line` unless `:per_summary` is what reproduces `stated`
        def strategy_for(lines, stated)
          return :per_line if stated.empty? || bucketed(lines, :per_line) == stated

          bucketed(lines, :per_summary) == stated ? :per_summary : :per_line
        end

        # @return [Hash{String => BigDecimal}] the `P_14_*` values a document states
        def stated_from(node, &reader)
          TAX_ELEMENTS.each_with_object({}) do |element, acc|
            value = reader.call(node, element)
            acc[element] = Formatting.decimal(value) unless value.nil?
          end
        end

        private

        # Several rate codes share one bucket — 23 and 22 both land in `P_14_1` — so the
        # comparison has to be made per bucket, not per rate.
        #
        # An unrecognised rate code is skipped rather than raised on. `VatRate.bucket` raises,
        # which meant a document carrying a rate the schema does not define was refused by
        # `parse` — but only when it also stated a `P_14_*`, since otherwise this method was
        # never reached. Inferring a rounding strategy is not the place to validate rate codes:
        # the inconsistency is worse than the leniency, and `#to_xml` still refuses the code
        # honestly when asked to write a bucket for it.
        def bucketed(lines, rounding)
          Summaries.vat_by_rate(lines, rounding).each_with_object({}) do |(code, amount), acc|
            # Zero-rated and exempt buckets have no tax element at all (§8.1a); there is
            # nothing in the document to compare against.
            element = VatRate::BUCKETS[code.to_s]&.last
            next if element.nil?

            acc[element] = (acc[element] || BigDecimal(0)) + amount
          end
        end
      end
    end
  end
end
