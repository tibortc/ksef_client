# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/fa3_corpus"

# Tier 3, the business tier (DESIGN.md §7.7) — and the `P_15` defect that grounding it found.
#
# The rule here is the only one that needs no upstream catalogue: `P_13_1` *is* a sum, per the
# XSD's own annotation, so checking that the buckets add up to `P_15` is arithmetic rather than
# policy (docs/REFERENCE.md §15.6, §17). Its two exceptions are measured, not reasoned — one
# grosz of tolerance and a guard for absent buckets, both forced by the Ministry's own corpus.
RSpec.describe Ksef::FA3::BusinessValidator do
  def sample(relative) = Ksef::FA3.parse(FA3Corpus.read(relative))

  describe "the Ministry's own worked examples" do
    # The strongest statement available: 22 real invoices the Ministry published as correct,
    # and the rule accuses none of them. A rule that fired here would be wrong by definition.
    FA3Corpus::MINISTRY_MODELLED.each do |relative|
      it "#{relative} reconciles" do
        expect(described_class.errors_for(Ksef::FA3.parse(FA3Corpus.read(relative)))).to be_empty
      end
    end
  end

  describe "the two samples that fix the rule's shape" do
    # 1666.66 + 383.33 + 0.95 + 0.05 = 2050.99 against a stated P_15 of 2051. Tax is rounded
    # per bucket and the total is not, so a grosz falls out. Without the tolerance the rule
    # rejects the Ministry's first example.
    it "tolerates Przykład 1's one grosz, which is bucket-level tax rounding" do
      invoice = sample("mf-samples/przyklad-01.xml")

      expect(invoice.summary_buckets.values.sum(BigDecimal(0))).to eq(BigDecimal("2050.99"))
      expect(invoice.gross_total).to eq(BigDecimal("2051"))
      expect(described_class.errors_for(invoice)).to be_empty
    end

    # A UPR may state P_15 and no breakdown at all. Summing nothing gives zero, so without the
    # guard the rule reports it as 450 out.
    it "says nothing about Przykład 16, which states P_15 and no buckets" do
      invoice = sample("mf-samples/przyklad-16.xml")

      expect(invoice.summary_buckets).to be_empty
      expect(invoice.gross_total).to eq(BigDecimal("450"))
      expect(described_class.errors_for(invoice)).to be_empty
    end

    # P_14_1W is the PLN equivalent of P_14_1, not a second tax. Counting it gives 30714.96
    # against a P_15 of 16678.80 and fails a correct invoice.
    it "excludes the W twins, which would otherwise double-count Przykład 20's tax" do
      invoice = sample("mf-samples/przyklad-20.xml")

      expect(invoice.summary_buckets.keys).to eq(%w[P_13_1 P_14_1])
      expect(described_class.errors_for(invoice)).to be_empty
    end
  end

  describe "when the figures disagree" do
    let(:correction) { sample("mf-samples/przyklad-06.xml") }

    it "reports a stated summary whose buckets miss its P_15" do
      out = correction.with(totals: correction.totals.with(gross: "-49950.00"))

      expect(out.errors.map(&:to_s))
        .to include(/summary: does not reconcile: the rate buckets sum to -50000\.00 but P_15 states -49950\.00/)
    end

    it "names the difference, so the reader does not have to subtract" do
      out = correction.with(totals: correction.totals.with(gross: "-49950.00"))

      expect(out.errors.first.message).to include("a difference of -50.00")
    end

    # The boundary is inclusive on purpose: one grosz is exactly what Przykład 1 is out by.
    it "tolerates exactly one grosz, in both directions" do
      %w[-49999.99 -50000.01].each do |gross|
        edge = correction.with(totals: correction.totals.with(gross: gross))

        expect(described_class.errors_for(edge)).to be_empty, gross
      end
    end

    it "reports two grosze, so the tolerance is a grosz and not a band" do
      out = correction.with(totals: correction.totals.with(gross: "-49999.98"))

      expect(described_class.errors_for(out).size).to eq(1)
    end
  end

  describe "a derived summary" do
    # A VAT invoice computes its buckets from its rows, so they agree by construction — until
    # `stated_gross` gives the comparison a second, independent figure to disagree with.
    it "reconciles when nothing states a gross of its own" do
      built = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "Acme",
                 address: { street: "ul. Testowa 1", city: "Warszawa", postal_code: "00-001" }
        f.buyer  nip: "1111111111", name: "Klient",
                 address: { street: "ul. Inna 2", city: "Kraków", postal_code: "30-001" }
        f.number "FV/1"
        f.issue_date "2026-08-26"
        f.line name: "Consulting", qty: 2, unit: "szt.", net_unit_price: "100", vat: "23"
      end

      expect(built.stated_gross).to be_nil
      expect(built.summary_buckets).to eq("P_13_1" => BigDecimal("200"), "P_14_1" => BigDecimal("46"))
      expect(described_class.errors_for(built)).to be_empty
    end

    it "reports a stated P_15 that the rows cannot account for" do
      invoice = sample("mf-samples/przyklad-01.xml").with(stated_gross: "2500.00")

      expect(described_class.errors_for(invoice).map(&:to_s))
        .to include(/buckets sum to 2050\.99 but P_15 states 2500\.00/)
    end
  end

  # The defect that grounding this rule uncovered. `P_15` is `minOccurs="1"`, so every document
  # states one — and a VAT invoice derived it instead of reading it, which re-emitted the
  # Ministry's own first example a grosz cheaper with every diagnostic silent.
  describe Ksef::FA3::Invoice do
    it "keeps the document's P_15 when deriving would change it" do
      invoice = sample("mf-samples/przyklad-01.xml")

      expect(invoice.stated_gross).to eq(BigDecimal("2051"))
      expect(invoice.to_xml).to include("<P_15>2051.00</P_15>")
    end

    it "re-serialises every modelled sample's P_15 unchanged" do
      drift = FA3Corpus::MINISTRY_MODELLED.filter_map do |relative|
        source = FA3Corpus.read(relative)
        stated = source[%r{<P_15>([^<]*)</P_15>}, 1]
        emitted = Ksef::FA3.parse(source).to_xml[%r{<P_15>([^<]*)</P_15>}, 1]
        relative if BigDecimal(stated) != BigDecimal(emitted)
      end

      expect(drift).to be_empty
    end

    # nil means "derive me", exactly as `Line#row_number` means "number me by position".
    # Stored unconditionally it would make a built invoice unequal to itself parsed back.
    it "leaves it nil when the derived figure already matches" do
      expect(sample("mf-samples/przyklad-04.xml").stated_gross).to be_nil
    end

    # `net_amount:` and `issued_at:` are both stated explicitly, and both are dodges around
    # **separate, known** asymmetries rather than incidental. A line built with a quantity and
    # a price and no net serialises a derived `P_11` that parses back into `net_amount`; an
    # invoice with no `issued_at` gets one written at serialisation and reads it back. In each
    # case the built invoice and the parsed one differ in a field the caller never set. Both
    # predate `stated_gross` and are the same shape as it — a value the document must carry
    # that the model derives instead of holding — and fixing either belongs with its own
    # measurement rather than folded in here.
    it "keeps a built invoice equal to itself parsed back" do
      built = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "Acme",
                 address: { street: "ul. Testowa 1", city: "Warszawa", postal_code: "00-001" }
        f.buyer  nip: "1111111111", name: "Klient",
                 address: { street: "ul. Inna 2", city: "Kraków", postal_code: "30-001" }
        f.number "FV/1"
        f.issue_date "2026-08-26"
        f.issued_at "2026-08-26T09:00:00Z"
        f.line name: "Consulting", qty: 3, unit: "szt.", net_unit_price: "150.125",
               net_amount: "450.38", vat: "23"
      end

      expect(Ksef::FA3.parse(built.to_xml)).to eq(built)
    end

    # Two sources for one figure is one too many: a stated summary already carries its gross.
    it "ignores a stated gross when the invoice states a whole summary" do
      totals = Ksef::FA3::Totals.new(gross: "100.00", buckets: { "P_13_1" => "100.00" })
      invoice = sample("mf-samples/przyklad-06.xml").with(totals: totals, stated_gross: "999.00")

      expect(invoice.stated_gross).to be_nil
      expect(invoice.gross_total).to eq(BigDecimal("100"))
    end
  end

  describe "the catalogue" do
    # Kept deliberately small and deliberately visible: §15.6 searched all 77 upstream files
    # and found no reconciliation rule at all, so anything beyond arithmetic-from-definitions
    # would be invented. This asserts the honest state rather than an aspiration.
    it "holds exactly the rules that need no upstream catalogue" do
      expect(described_class::RULES).to eq(%i[summary_reconciliation])
      expect(described_class::RULES).to all(satisfy { |rule| described_class.respond_to?(rule) })
    end
  end
end
