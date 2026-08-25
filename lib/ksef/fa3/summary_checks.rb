# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a's checks on {Totals} — the summary an invoice **states** rather than derives.
    #
    # Its own module because the rule spans two families that share nothing else. A correction
    # states its summary because the buckets are deltas its rows need not determine (§8.4); an
    # advance or settlement invoice states one because the rows describe the goods while the
    # buckets describe money this document does not contain enough to compute (§8.5).
    #
    # ## Both directions are checked, and the second is why this module exists
    #
    # **Set where it does not belong**: emitted verbatim, never read back, and free to
    # contradict the rows with nothing to notice.
    #
    # **Absent where it is needed**: the summary falls through to {DocumentMapping}'s
    # line-derived buckets. That fallback shipped once — a `KOR` built without stated totals
    # counted its `StanPrzed` rows as sales and emitted a refund as a charge, XSD-valid and
    # tier 1 silent (§8.4b). The rule below is what closed it, generalised as the family grew.
    module SummaryChecks
      # Included rather than assumed present: constant lookup is lexical.
      include FieldChecks

      # The three constructs that mean "the rows do not determine the summary". Each is
      # structural — an element the document either carries or does not — rather than a
      # judgement about the arithmetic, which is tier 3's and is not built.
      DERIVATION_BLOCKERS = {
        "a line is marked state_before" =>
          ->(invoice) { invoice.lines.any? { |line| line.is_a?(Line) && line.state_before } },
        "an order is stated" => ->(invoice) { !invoice.order.nil? },
        "an advance invoice is settled" => ->(invoice) { !invoice.advances.empty? }
      }.freeze

      private

      # {Totals} validates its own bucket names and coerces its own amounts, so there is
      # nothing left to check about a real one — only that it *is* one, and that the invoice
      # is a kind that states its summary at all.
      #
      # **`is_a?`, not `respond_to?(:to_fa3)`.** Duck-typing here re-opened the hole this check
      # was added to close: a {Line} or a {Subject} also answers `to_fa3`, so one passed the
      # model tier and then made `#to_xml` raise `ArgumentError: missing keyword` — outside
      # this gem's hierarchy and so outside {Invoice#errors}' rescue.
      def totals_errors(invoice)
        totals = invoice.totals
        return [] if totals.nil?
        return [Issue.new(field: "totals", message: "is not a Ksef::FA3::Totals")] unless totals.is_a?(Totals)
        return [] if Invoice::STATED_TOTALS_TYPES.include?(invoice.invoice_type)

        [Issue.new(field: "totals",
                   message: "is set on a #{invoice.invoice_type} invoice, whose summary this " \
                            "model computes from its lines. A stated summary is emitted " \
                            "verbatim and never read back, so the document would disagree " \
                            "with its own rows (docs/REFERENCE.md §8.4)")]
      end

      # Scoped to what the document carries rather than to its `RodzajFaktury`: a correction
      # whose rows already *are* the deltas computes correctly, and the Ministry's Przykład 3
      # is exactly that shape, so refusing every correction would reject a worked example.
      def derived_summary_errors(invoice)
        return [] unless invoice.totals.nil?

        reason = DERIVATION_BLOCKERS.find { |_, blocks| blocks.call(invoice) }&.first
        return [] if reason.nil?

        [Issue.new(field: "totals",
                   message: "is required when #{reason}. The rows then describe something " \
                            "other than this invoice's own amounts, so deriving the summary " \
                            "from them states a figure the document does not mean " \
                            "(docs/REFERENCE.md §8.4, §8.5)")]
      end
    end
  end
end
