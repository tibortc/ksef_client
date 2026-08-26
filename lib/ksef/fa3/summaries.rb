# frozen_string_literal: true

module Ksef
  module FA3
    # The summary arithmetic of an invoice: what each rate code contributes, and the three
    # totals the document carries.
    #
    # Extracted from {Invoice} on 2026-08-26, when tier 3 arrived and gave these methods a
    # second caller. Two reasons beyond the class-length gate. They are one coherent subject —
    # every one of them answers "what does this invoice come to?" — and {BusinessValidator}
    # reconciles against them, so it helps to have somewhere to point at rather than a span of
    # a 300-line class.
    #
    # The `:per_line` / `:per_summary` split lives here too. Both are permitted by Polish VAT
    # law and they differ by a grosz, which is why the strategy is an explicit field rather
    # than a choice this gem makes quietly (DESIGN.md §7.3).
    module Summaries
      class << self
        # The same arithmetic as the instance methods, over a bare line list — so
        # {Invoice#initialize} can ask "what would this invoice derive?" before there is an
        # invoice to ask. That is what lets `stated_gross` canonicalise in the **model**,
        # where {Invoice.positioned} canonicalises `row_number`, rather than only in the
        # parser (docs/REFERENCE.md §17.2).
        def net_by_rate(lines)
          summable(lines).each_with_object({}) do |line, acc|
            acc[line.vat_rate] = (acc[line.vat_rate] || BigDecimal(0)) + line.net
          end
        end

        # **`StanPrzed` rows are excluded, and that is a correctness fix rather than a tidy.**
        # A row marked "stan przed korektą" states the position *as it was*; a correction shows
        # it beside its replacement. Adding the two together answers a question nobody asked:
        # on the Ministry's Przykład 2 it gave 3089.42 — 1626.01 before plus 1463.41 after —
        # against a `net_total` of −162.60. A caller building a per-rate VAT report over
        # downloaded invoices got a figure nineteen times the truth, with no error and a
        # passing `#valid?`.
        #
        # Nothing that *derives* a summary is affected: tier 1's `SummaryChecks` already
        # refuses a `state_before` row on an invoice that derives, so these rows only ever
        # appear where the summary is stated.
        #
        # A non-{Line} entry is skipped rather than raised on, matching what
        # `ModelValidator#line_errors` and `SummaryChecks` already tolerate — this runs inside
        # `Invoice.new`, and blowing up here would turn a reportable tier-1 issue into a
        # `NoMethodError` outside this gem's hierarchy.
        def summable(lines)
          lines.select { |line| line.is_a?(Line) && !line.state_before && line.summarised? }
        end

        def vat_by_rate(lines, rounding)
          return per_line(lines) if rounding == :per_line

          per_summary(net_by_rate(lines))
        end

        # @return [BigDecimal] what {Invoice#gross_total} would answer with nothing stated
        def derived_gross(lines, rounding)
          net_by_rate(lines).values.sum(BigDecimal(0)) +
            vat_by_rate(lines, rounding).values.sum(BigDecimal(0))
        end

        # Round each line, then sum. Matches an ERP that prices line by line.
        def per_line(lines)
          summable(lines).each_with_object({}) do |line, acc|
            acc[line.vat_rate] = (acc[line.vat_rate] || BigDecimal(0)) + line.vat
          end
        end

        # Sum the nets, then round once. Fewer rounding events, so it can differ from
        # :per_line by a grosz — which is exactly why the choice is explicit.
        def per_summary(nets)
          nets.to_h do |code, net|
            percentage = VatRate.percentage(code)
            rounded = percentage ? (net * percentage / 100).round(Formatting::AMOUNT_SCALE) : BigDecimal(0)
            [code, rounded]
          end
        end
      end

      # **This is what the *lines* say**, always — {Invoice#totals} does not enter into it,
      # because a stated summary is keyed by bucket and cannot be resolved back to rate codes
      # (§8.1a). For a correction that states its own summary the two are different questions,
      # and an invoice with no lines answers `{}` here while {#net_total} answers what the
      # document declares.
      #
      # @return [Hash{String => BigDecimal}] rate code => net, insertion-ordered by first
      #   appearance so the serialiser's output is stable for a given invoice
      # A row with no amount, or none with a rate to bucket it under, contributes nothing. It
      # is legal — see {Line#net} — and tier 1 is what stops one appearing on an invoice that
      # derives its summary from its rows.
      def net_by_rate = Summaries.net_by_rate(lines)

      # @return [Hash{String => BigDecimal}]
      def vat_by_rate = Summaries.vat_by_rate(lines, rounding)

      # The three figures the document actually carries: read from {Invoice#totals} when the
      # invoice states them, computed from the lines otherwise.
      def net_total = totals ? totals.net : net_by_rate.values.sum(BigDecimal(0))
      def vat_total = totals ? totals.vat : vat_by_rate.values.sum(BigDecimal(0))

      # A stated `P_15` wins over a derived one — it is what the document says is owed, and
      # bucket-level rounding means the derivation can be a grosz out
      # ({Invoice.scaled_gross}).
      def gross_total = totals&.gross || stated_gross || (net_total + vat_total)
    end
  end
end
