# frozen_string_literal: true

module Ksef
  module FA3
    # **Tier 3 — the business tier** (DESIGN.md §7.7): reconciliation rules that a document
    # can satisfy the XSD and still fail on. Tiers 1 and 2 ask whether the fields are present,
    # well-typed and well-formed; this one asks whether they *agree with each other*.
    #
    # ## Why this tier is nearly empty, and why that is the honest state
    #
    # There is no upstream catalogue to implement. `docs/REFERENCE.md` §15.6 records the
    # search: **no file in `ksef-api` states a reconciliation rule** — not that `P_15` equals
    # its buckets, not what a correction's references must satisfy, not an error code for an
    # arithmetic mismatch. The one business validation KSeF ever proposed (issue #837, a
    # currency rule) was **withdrawn back to analysis** after it turned out to reject legal
    # invoices, and the Ministry's own remark in that thread — that no production invoice
    # violated it — is evidence the service today enforces nothing beyond the schema.
    #
    # So this tier is built on the *one* grounding that needs no catalogue: arithmetic that
    # follows from what the XSD's own annotations say a field **is**. `P_13_1` is documented
    # as a sum; checking a sum is not policy. Everything else waits, and §15.6's warning is
    # the standing instruction — **do not synthesise rules from Polish VAT law and record them
    # as verified facts.** The catalogue grows as evidence arrives; the engine is here so that
    # adding one is a line in {RULES} rather than a redesign.
    #
    # ## It reports; it does not refuse
    #
    # Tier 3 findings are `Issue` values like any other, addressed to `summary`. A caller who
    # wants them fatal gets that from {Invoice#validate!}; a caller reading a document to find
    # out why KSeF rejected it still gets the document.
    module BusinessValidator
      # One grosz. Not a fudge factor — a **consequence of the field definitions**: each
      # `P_14_x` is the tax on its own bucket, rounded to `TKwotowy`'s two places, while
      # `P_15` is the amount actually owed. Rounding several buckets and adding them need not
      # equal the total, and the Ministry's Przykład 1 is the proof: `1666.66 + 383.33 + 0.95
      # + 0.05` is `2050.99` against a stated `P_15` of `2051`.
      #
      # A tolerance of exactly one grosz is what the corpus supports and no more. It is *not*
      # scaled by the number of buckets, which would be the theoretically tidier choice and
      # would also be an invention: 24 of the 26 samples reconcile exactly and the twenty-fifth
      # is out by one, so there is no evidence for a wider band (docs/REFERENCE.md §17.1).
      TOLERANCE = BigDecimal("0.01")

      MISMATCH = "does not reconcile: the rate buckets sum to %<sum>s but P_15 states " \
                 "%<gross>s, a difference of %<delta>s. Per-bucket tax rounding accounts for " \
                 "at most one grosz (docs/REFERENCE.md §17.1)."

      # Each rule is a method name taking the invoice and answering an {Issue} or nil. Adding
      # a rule is adding a method and a name here — and, per §15.6, a ledger entry saying what
      # grounds it.
      RULES = %i[summary_reconciliation].freeze

      class << self
        # @param invoice [Invoice]
        # @return [Array<Issue>] empty when nothing is out of agreement
        def errors_for(invoice)
          RULES.filter_map { |rule| public_send(rule, invoice) }
        end

        # `Σ P_13_* + Σ P_14_* == P_15`, within {TOLERANCE}.
        #
        # **Measured, not read.** It holds in 24 of the Ministry's 26 worked examples, which is
        # what fixes its shape — the two that miss are why the tolerance and the guard below
        # both exist, and a rule without them rejects the Ministry's own first example.
        #
        # The `W` twins are excluded, and that is load-bearing rather than tidy: `P_14_1W` is
        # the **PLN equivalent** of `P_14_1` on a foreign-currency invoice, not a second tax.
        # Przykład 20 states `P_13_1` 13560, `P_14_1` 3118.80 and `P_14_1W` 14036.16 against a
        # `P_15` of 16678.80 — including the twin gives 30714.96 and fails a correct invoice.
        # {Totals::ELEMENTS} already excludes them, so this reads that list rather than
        # re-deriving one.
        def summary_reconciliation(invoice)
          # {Invoice#summary_buckets} is the figures **as the document will carry them** —
          # rounded per bucket, exactly as `#to_xml` rounds them. Comparing unrounded
          # BigDecimals would test something the document is not, and would pass invoices the
          # Ministry's own corpus shows to be a grosz out.
          buckets = invoice.summary_buckets
          # **The guard, and what it is for.** A `UPR` may state `P_15` alone — Przykład 16
          # does, 450 with no buckets at all. Summing nothing gives zero, so without this the
          # rule reports every such invoice as 450 out. No buckets means no breakdown to
          # reconcile against, which is not the same as a breakdown that disagrees.
          return nil if buckets.empty?

          sum = buckets.values.sum(BigDecimal(0))
          delta = sum - invoice.gross_total
          return nil if delta.abs <= TOLERANCE

          mismatch(sum, invoice.gross_total, delta)
        end

        def mismatch(sum, gross, delta)
          Issue.new(field: "summary", message: format(
            MISMATCH, sum: Formatting.amount(sum),
                      gross: Formatting.amount(gross), delta: Formatting.amount(delta)
          ))
        end
      end
    end
  end
end
