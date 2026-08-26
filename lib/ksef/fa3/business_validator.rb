# frozen_string_literal: true

module Ksef
  module FA3
    # **Tier 3 — the business tier** (DESIGN.md §7.7): reconciliation between figures a
    # document states independently of one another. It answers a question the other tiers
    # cannot — do these numbers agree? — and it answers it as a **warning**.
    #
    # ## Why it holds one rule, and why that rule cannot be an error
    #
    # There is no upstream catalogue to implement. `docs/REFERENCE.md` §15.6 records the
    # search: no file in `ksef-api` states a reconciliation rule, and the one business
    # validation KSeF ever proposed was **withdrawn back to analysis** after the community
    # showed it rejected legal invoices.
    #
    # The rule here is grounded **empirically** — §15.6's grounding 3, measurement over the
    # Ministry's 26 worked examples — and not definitionally. That distinction was got wrong
    # once already and is worth stating plainly: `P_15` is annotated *"Kwota należności
    # ogółem"* and says nothing about the buckets, and §15.6's own sentence is "Nothing says
    # `P_15` equals the sum of the rate buckets." The definitional rule one might reach for
    # instead — `P_13_1` is a *sum*, so check it against the rows — is **not implementable
    # here**: ten of the fourteen modelled stated-summary samples falsify it, because a
    # correction's buckets are deltas, an advance's are pre-payments and a settlement's are
    # remainders (§8.4, §8.5).
    #
    # **And a Polish invoice priced from round gross prices routinely fails this rule while
    # being perfectly legal.** The Ministry's own Przykład 1 is one: its nets are back-computed
    # *w stu* from gross prices of 2000/50/1 and rounded down, so the buckets sum a grosz under
    # `P_15`. The gap grows with the number of such lines — two of them and it is two grosze —
    # so **no tolerance sized from this corpus can be sound**, because the corpus never varies
    # the dimension the error scales with. A tier that refused those invoices would repeat
    # precisely the mistake that got issue #837 withdrawn.
    #
    # So this reports and never refuses: {Invoice#warnings}, not `#errors`, and nothing here
    # can block {Ksef::Client#send_invoice}. That is the §14.3 precedent — the UPO
    # receiving-party mismatch is a warning for the same reason, so that a schema opinion
    # cannot stand between a legal document and its being filed.
    module BusinessValidator
      # One grosz, and **honestly arbitrary beyond that**. It is what the single corpus witness
      # shows and no more: 22 of the 26 samples reconcile to the cent, Przykład 1 misses by
      # 0.01, and three state no buckets to reconcile at all. It is not derived from rounding
      # arithmetic — per-bucket tax rounding moves Przykład 1's total by 0.0007, not by a
      # grosz — so it neither is nor pretends to be a bound (docs/REFERENCE.md §17.1).
      TOLERANCE = BigDecimal("0.01")

      MISMATCH = "the rate buckets sum to %<sum>s but P_15 states %<gross>s, a difference of " \
                 "%<delta>s. This is often legitimate — an invoice whose nets are computed " \
                 "back from round gross prices differs by a grosz or so per line — and KSeF " \
                 "is not known to reject it. Worth checking against your source figures " \
                 "(docs/REFERENCE.md §17.1)."

      # Each rule is a public singleton method taking the invoice and answering an {Issue} or
      # nil. Adding one means adding a method, a name here, and — per §15.6 — a ledger entry
      # saying what grounds it.
      RULES = %i[summary_reconciliation].freeze

      class << self
        # @param invoice [Invoice]
        # @return [Array<Issue>] advisory; empty when nothing disagrees
        def warnings_for(invoice)
          RULES.filter_map { |rule| public_send(rule, invoice) }
        end

        # `Σ P_13_* + Σ P_14_* ≈ P_15`, over **what the document states**.
        #
        # It compares two figures the *document* carries independently. It deliberately does
        # not reconcile a derived summary against a derived total: those come from the same
        # rows, so a difference measures this model's own rounding regime rather than anything
        # about the invoice — and it did, before the 2026-08-26 audit, which is how an ordinary
        # built invoice came to be accused of a two-grosz error.
        #
        # Reading the buckets from the document rather than from the model also keeps the rule
        # honest about what it cannot represent: a document using `P_13_5`/`P_14_5` (OSS) or
        # `P_13_11` (margin) states buckets no rate code reaches ({VatRate.unreachable_elements}),
        # and comparing the model's derivation against the document's total accused those of an
        # arithmetic error that was really this model's own incompleteness.
        def summary_reconciliation(invoice)
          stated = stated_summary(invoice)
          return nil if stated.nil? || stated[:buckets].empty?

          sum = stated[:buckets].values.sum(BigDecimal(0))
          delta = sum - stated[:gross]
          delta.abs <= TOLERANCE ? nil : mismatch(sum, stated[:gross], delta)
        end

        # @return [Hash, nil] `{buckets:, gross:}` as stated, or nil when nothing states them
        #   independently — a built invoice derives both from its rows and has nothing to
        #   reconcile against itself.
        def stated_summary(invoice)
          return { buckets: invoice.totals.buckets, gross: invoice.totals.gross } if invoice.totals

          document_summary(invoice.raw_document)
        end

        # The `W` twins are excluded, and that is load-bearing rather than tidy: `P_14_1W` is
        # the **PLN equivalent** of `P_14_1` on a foreign-currency invoice, not a second tax —
        # Przykład 20 states 13560 + 3118.80 against a `P_15` of 16678.80, and counting its
        # 14036.16 twin gives 30714.96. {Totals::ELEMENTS} is the list, built from the
        # generated schema metadata, so there is one definition of "a bucket".
        def document_summary(document)
          return nil if document.nil?

          fa = document.dup.remove_namespaces!.at_xpath("//Fa")
          gross = fa&.at_xpath("P_15")&.text
          return nil if gross.nil?

          { buckets: buckets_in(fa), gross: Formatting.decimal(gross) }
        end

        def buckets_in(node)
          Totals::ELEMENTS.each_with_object({}) do |name, found|
            text = node.at_xpath(name)&.text
            found[name] = Formatting.decimal(text) unless text.nil?
          end
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
