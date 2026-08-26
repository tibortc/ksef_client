# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/fa3_corpus"

# Tier 3, the business tier (DESIGN.md §7.7) — **advisory**, and the audit of 2026-08-26 is
# why. It reconciles two figures a *document* states independently of one another; it never
# reconciles a derived summary against a derived total, because those come from the same rows
# and any difference measures this model's rounding rather than the invoice. And it warns
# rather than erring, because an invoice whose nets are computed back from round gross prices
# legitimately misses by a grosz per line — the shape of the Ministry's own Przykład 1, and the
# shape that got KSeF's proposed business rule withdrawn (docs/REFERENCE.md §15.6, §17.1).
RSpec.describe Ksef::FA3::BusinessValidator do
  def sample(relative) = Ksef::FA3.parse(FA3Corpus.read(relative))

  def built(**overrides)
    Ksef::FA3.build do |f|
      f.seller nip: "9999999999", name: "Acme",
               address: { street: "ul. Testowa 1", city: "Warszawa", postal_code: "00-001" }
      f.buyer  nip: "1111111111", name: "Klient",
               address: { street: "ul. Inna 2", city: "Kraków", postal_code: "30-001" }
      f.number "FV/1"
      f.issue_date "2026-08-26"
      f.issued_at "2026-08-26T09:00:00Z"
      # `net_amount:` is stated because a line built from quantity and price alone serialises a
      # derived `P_11` that parses back *into* `net_amount` — a separate open asymmetry
      # (docs/REFERENCE.md §17.3), and not what these examples are about.
      (overrides[:lines] || [{ name: "Consulting", qty: 2, unit: "szt.", net_unit_price: "100",
                               net_amount: "200", vat: "23" }]).each { |line| f.line(**line) }
    end
  end

  describe "the Ministry's own worked examples" do
    FA3Corpus::MINISTRY_MODELLED.each do |relative|
      it "#{relative} raises no warning" do
        expect(Ksef::FA3.parse(FA3Corpus.read(relative)).warnings).to be_empty
      end
    end
  end

  describe "what it refuses to compare" do
    # The regression the audit found. Three fractional lines, priced the way DESIGN.md §8's own
    # snippet prices them, produced a summary whose buckets are each rounded against a total
    # that is not — a difference of this model's own making. Reported as an invoice defect, it
    # made `Ksef::Client#send_invoice` refuse a perfectly legal document.
    it "says nothing about a built invoice, which states nothing independently" do
      invoice = built(lines: [
                        { name: "Wolowina", qty: "2.5", unit: "kg", net_unit_price: "42.99", vat: "5" },
                        { name: "Sok", qty: "1.5", unit: "l", net_unit_price: "8.19", vat: "23" },
                        { name: "Chleb", qty: "3.5", unit: "kg", net_unit_price: "6.57", vat: "8" }
                      ])

      expect(invoice.warnings).to be_empty
      expect(invoice.errors).to be_empty
      expect(invoice).to be_valid
    end

    # A document may state buckets no rate code reaches — P_13_5/P_14_5 (OSS) and P_13_11
    # (margin scheme). Reconciling the model's derivation against the document's total accused
    # such an invoice of the model's own incompleteness. Reading both sides from the document
    # removes the question.
    it "reads the document's own buckets, so a margin-scheme invoice is not accused" do
      source = FA3Corpus.read("mf-samples/przyklad-04.xml")
                        .sub("<P_15>64279.92</P_15>", "<P_13_11>1000.00</P_13_11><P_15>65279.92</P_15>")
      invoice = Ksef::FA3.parse(source)

      expect(Ksef::FA3::Validator.errors_for(source)).to be_empty
      expect(invoice.unmapped_elements).to include("Faktura/Fa/P_13_11")
      expect(invoice.warnings).to be_empty
    end

    # The parser does not validate, so a document it read may be missing `P_15` entirely —
    # `Fa` is required, `P_15` within it is not enforced by anything the parser runs.
    it "says nothing when the document states no P_15 to reconcile against" do
      source = FA3Corpus.read("mf-samples/przyklad-01.xml").sub(%r{<P_15>[^<]*</P_15>}, "")
      invoice = Ksef::FA3.parse(source)

      expect(invoice.warnings).to be_empty
      # And the model fills one in on the way out, from the rows — which is exactly why there
      # is nothing independent left to reconcile against.
      expect(invoice.stated_gross).to be_nil
      expect(invoice.to_xml).to include("<P_15>2050.99</P_15>")
    end

    # `raw_document` is a public constructor field, so a caller can hand over something that is
    # not an FA(3) document at all. Answering nil beats raising from an advisory check.
    it "says nothing when the retained document has no Fa element" do
      invoice = built.with(raw_document: Nokogiri::XML("<somethingElse/>"))

      expect(invoice.warnings).to be_empty
    end

    it "says nothing when the document states no buckets, as Przykład 16 does" do
      invoice = sample("mf-samples/przyklad-16.xml")

      expect(invoice.summary_buckets).to be_empty
      expect(invoice.gross_total).to eq(BigDecimal("450"))
      expect(invoice.warnings).to be_empty
    end
  end

  describe "when the document's own figures disagree" do
    let(:correction) { sample("mf-samples/przyklad-06.xml") }

    it "warns, naming both figures and the difference" do
      out = correction.with(totals: correction.totals.with(gross: "-49950.00"))

      expect(out.warnings.map(&:to_s))
        .to include(/summary: the rate buckets sum to -50000\.00 but P_15 states -49950\.00/)
      expect(out.warnings.first.message).to include("a difference of -50.00")
    end

    # The whole point of the redesign: a warning must never make an invoice invalid, or the
    # gem refuses to file legal documents.
    it "never makes the invoice invalid, and never blocks a send" do
      out = correction.with(totals: correction.totals.with(gross: "-49950.00"))

      expect(out.errors).to be_empty
      expect(out).to be_valid
      expect { out.validate! }.not_to raise_error
    end

    it "tolerates exactly one grosz, in both directions" do
      %w[-49999.99 -50000.01].each do |gross|
        expect(correction.with(totals: correction.totals.with(gross: gross)).warnings).to be_empty, gross
      end
    end

    # Pins the tolerance's *shape*: a band scaled by bucket count would swallow this.
    # Przykład 6 states two buckets, so any per-bucket scaling doubles the band past 0.02.
    it "warns at two grosze, so the tolerance is a grosz and not a band" do
      out = correction.with(totals: correction.totals.with(gross: "-49999.98"))

      expect(out.warnings.size).to eq(1)
    end

    it "warns on a parsed invoice whose stated P_15 its own buckets cannot reach" do
      source = FA3Corpus.read("mf-samples/przyklad-01.xml").sub("<P_15>2051</P_15>", "<P_15>2500.00</P_15>")

      expect(Ksef::FA3.parse(source).warnings.map(&:to_s))
        .to include(/buckets sum to 2050\.99 but P_15 states 2500\.00/)
    end
  end

  # `P_14_1W` is the PLN equivalent of `P_14_1`, not a second tax. No Ministry sample pairs a
  # stated summary with a W twin, so this is the only place the exclusion is decisive — the
  # earlier example named for it cited Przykład 20, whose summary is *derived*, where no W
  # element can ever appear whatever the list says.
  describe "the W twins" do
    it "are not counted as buckets" do
      source = FA3Corpus.read("mf-samples/przyklad-06.xml")
                        .sub("<P_14_1>-9349.59</P_14_1>", "<P_14_1>-9349.59</P_14_1><P_14_1W>-9999.00</P_14_1W>")
      invoice = Ksef::FA3.parse(source)

      expect(invoice.warnings).to be_empty
      expect(Ksef::FA3::Totals::ELEMENTS).not_to include("P_14_1W")
    end
  end

  describe Ksef::FA3::Invoice do
    it "keeps the document's P_15 when deriving would change it" do
      invoice = sample("mf-samples/przyklad-01.xml")

      expect(invoice.stated_gross).to eq(BigDecimal("2051"))
      expect(invoice.to_xml).to include("<P_15>2051.00</P_15>")
    end

    it "re-serialises every modelled sample's P_15 to the same number" do
      drift = FA3Corpus::MINISTRY_MODELLED.filter_map do |relative|
        source = FA3Corpus.read(relative)
        stated = source[%r{<P_15>([^<]*)</P_15>}, 1]
        emitted = Ksef::FA3.parse(source).to_xml[%r{<P_15>([^<]*)</P_15>}, 1]
        relative if BigDecimal(stated) != BigDecimal(emitted)
      end

      expect(drift).to be_empty
    end

    # nil means "derive me". Canonicalised in the **constructor**, so `Invoice.new` and `#with`
    # obey it too — it lived only in the parser until the audit, and those two public doors
    # bypassed it and broke DESIGN.md §7.6 with no diagnostic.
    it "drops a stated gross that merely repeats what the rows derive" do
      base = built

      expect(base.gross_total).to eq(BigDecimal("246"))
      expect(base.with(stated_gross: "246.00").stated_gross).to be_nil
      expect(base.with(stated_gross: "246.00")).to eq(base)
      expect(Ksef::FA3.parse(base.with(stated_gross: "246.00").to_xml)).to eq(base)
    end

    it "keeps one that does not, and round-trips it" do
      differing = built.with(stated_gross: "246.01")

      expect(differing.stated_gross).to eq(BigDecimal("246.01"))
      expect(Ksef::FA3.parse(differing.to_xml)).to eq(differing)
    end

    # Every other money field rounds to its element's scale on the way in (§8.2b); this one
    # had no test, and dropping its `.round` left the whole suite green.
    it "rounds to the two places TKwotowy allows" do
      expect(built.with(stated_gross: "246.005").stated_gross).to eq(BigDecimal("246.01"))
      expect { built.with(stated_gross: 1.5) }.to raise_error(Ksef::ValidationError, /Float is not allowed/)
    end

    it "ignores a stated gross when the invoice states a whole summary" do
      totals = Ksef::FA3::Totals.new(gross: "100.00", buckets: { "P_13_1" => "100.00" })
      invoice = sample("mf-samples/przyklad-06.xml").with(totals: totals, stated_gross: "999.00")

      expect(invoice.stated_gross).to be_nil
      expect(invoice.gross_total).to eq(BigDecimal("100"))
    end

    # The parser does not validate (DESIGN.md §7.4). Reading a document to find out why KSeF
    # rejected it must keep working when P_15 is the thing that is wrong with it.
    it "parses a document whose P_15 is empty or unreadable, leaving the objection to tier 2" do
      %w[<P_15></P_15> <P_15>abc</P_15>].each do |broken|
        source = FA3Corpus.read("mf-samples/przyklad-01.xml").sub("<P_15>2051</P_15>", broken)

        expect { Ksef::FA3.parse(source) }.not_to raise_error, broken
        expect(Ksef::FA3.parse(source).stated_gross).to be_nil, broken
      end
    end

    # `#summary_buckets` is public API — "the summary as the document will carry it" — so the
    # rounding is the whole promise. Dropping it left the suite green.
    it "rounds summary_buckets to what the document will carry" do
      invoice = built(lines: [{ name: "A", qty: 1, unit: "szt.", net_unit_price: "100.005", vat: "23" }])

      expect(invoice.summary_buckets).to eq("P_13_1" => BigDecimal("100.01"), "P_14_1" => BigDecimal("23"))
      expect(invoice.to_xml).to include("<P_13_1>100.01</P_13_1>")
    end
  end

  describe "the catalogue" do
    # Deliberately small and deliberately visible: §15.6 searched all 77 upstream files and
    # found no reconciliation rule, so anything beyond this would be invented.
    it "holds exactly the rules that need no upstream catalogue" do
      expect(described_class::RULES).to eq(%i[summary_reconciliation])
      expect(described_class.method(:summary_reconciliation).arity).to eq(1)
    end
  end
end
