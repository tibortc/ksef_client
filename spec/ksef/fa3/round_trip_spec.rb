# frozen_string_literal: true

require_relative "../../support/fa3_corpus"

# DESIGN.md §7.6's round-trip law, run over the pinned sample corpus.
#
# The corpus is upstream's, from two CIRFMF repositories that are *not* `ksef-api` — it
# publishes no example invoice at all (docs/REFERENCE.md §1.4). That matters here: these are
# documents nobody in this project wrote, exercising elements the model does not have, which
# is the only way to find out what the parser does with a real invoice rather than with its
# own output.
RSpec.describe "the FA(3) round-trip law" do
  def sample(relative) = FA3Corpus.read(relative)

  describe "upstream's own samples" do
    FA3Corpus.upstream.each do |relative|
      context relative do
        let(:xml) { sample(relative) }
        let(:parsed) { Ksef::FA3.parse(xml) }

        it "parses" do
          expect(parsed.lines).not_to be_empty
          expect(parsed.number).to be_a(String)
        end

        # The law as DESIGN.md §7.6 states it: `serialize(parse(sample))` is XSD-valid. Not
        # byte-identical and not lossless — the model is smaller than FA(3) — but what comes
        # out is a document KSeF's schema accepts.
        it "re-serialises to a schema-valid document" do
          expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
        end

        # Idempotency: whatever was dropped was dropped on the first pass, and a second
        # round trip changes nothing further. This is what makes `parse` → `to_xml` a
        # predictable operation rather than one that erodes a document each time.
        it "is stable under a second round trip" do
          once = parsed.to_xml

          expect(Ksef::FA3.parse(once).to_xml).to eq(once)
        end

        # P_15 is recomputed from the lines on the way out, so this asserts that our
        # arithmetic agrees with the document's own stated total — read independently, out of
        # the raw upstream bytes. Asserted unconditionally: a trailing `if stated` would turn
        # a sample without a P_15 into an example with no expectations at all, which RSpec
        # reports as a pass.
        it "preserves the totals it read" do
          stated = Nokogiri::XML(xml).at_xpath("//*[local-name()='P_15']")&.text

          expect(stated).not_to be_nil
          expect(Ksef::FA3::Formatting.amount(parsed.gross_total)).to eq(stated)
        end
      end
    end
  end

  # The loop above generates its examples from a list. If that list came back empty the suite
  # would still pass, 24 examples lighter, with coverage unchanged — so the list itself needs
  # an assertion (see FA3Corpus::UPSTREAM).
  describe "the corpus wiring" do
    it "finds every pinned upstream sample" do
      expect(FA3Corpus.upstream).to match_array(FA3Corpus::UPSTREAM)
      expect(FA3Corpus::UPSTREAM.size).to eq(4)
    end

    it "reads them as non-empty FA(3) documents with the placeholders substituted" do
      FA3Corpus.upstream.each do |relative|
        xml = FA3Corpus.read(relative)
        expect(xml).to include("<Faktura"), relative
        expect(xml).not_to include("#nip#"), relative
      end
    end
  end

  describe "documents this gem wrote" do
    # Our own goldens are fully within the model, so for these the law is the strong one:
    # byte-for-byte, and nothing reported as lost.
    FA3Corpus.ours.each do |relative|
      it "#{relative} round-trips byte for byte, losing nothing" do
        xml = sample(relative)
        parsed = Ksef::FA3.parse(xml)

        expect(parsed.to_xml).to eq(xml)
        expect(parsed.unmapped_elements).to be_empty
        expect(parsed).to be_fully_mapped
      end
    end
  end

  describe "what the model does not carry" do
    let(:parsed) { Ksef::FA3.parse(sample("ksef-client-csharp/invoice-template-fa-3-with-custom-Subject3.xml")) }

    # The point of #raw_document and #unmapped_elements existing at all. This sample has a
    # third party, payment details, a delivery period and much else; re-serialising it drops
    # them, and a caller has to be able to find that out before deciding to.
    it "names the elements re-serialising would drop" do
      expect(parsed).not_to be_fully_mapped
      expect(parsed.unmapped_elements).to include("Faktura/Podmiot3", "Faktura/Fa/Platnosc")
    end

    it "retains the whole document regardless" do
      expect(parsed.raw_document).to be_a(Nokogiri::XML::Document)
      expect(parsed.raw_document.at_xpath("//*[local-name()='Podmiot3']")).not_to be_nil
    end

    # Paths are reported by element kind, not per occurrence: this sample has three rows,
    # and a caller wants to know that `CN` is unmapped, not that it is unmapped three times.
    it "collapses repeated elements to one path" do
      expect(parsed.unmapped_elements.count { |path| path == "Faktura/Fa/FaWiersz/CN" }).to eq(1)
    end
  end

  # docs/REFERENCE.md §15.1: this document is XSD-valid and KSeF rejects it, because it
  # carries C1 control characters. Tier 1 is what will catch it; tier 2 provably cannot, and
  # this is the fixture that proves it. Recorded here so the claim in the ledger has a test
  # behind it rather than a measurement someone took once.
  describe "the fixture that proves tier 2 is not enough" do
    let(:xml) { sample("ksef-client-csharp/invoice-template-fa-3-with-disallowed-unicode-characters.xml") }

    it "passes XSD validation despite carrying forbidden characters" do
      expect(Ksef::FA3::Validator.errors_for(xml)).to be_empty
    end

    it "really does contain characters from the forbidden ranges" do
      forbidden = xml.each_char.select { |char| (0x86..0x9F).cover?(char.ord) }

      expect(forbidden.map(&:ord).uniq).to contain_exactly(0x87, 0x9B)
    end

    # And it parses: reading a document in order to find out why it was rejected is a normal
    # thing to want, so the parser must not be the thing that refuses it.
    it "parses anyway, because parsing is not validating" do
      expect(Ksef::FA3.parse(xml).lines.size).to eq(3)
    end
  end

  # The Ministry's own twenty-six worked examples (docs/REFERENCE.md §1.5). They matter for two
  # opposite reasons: the twelve `VAT` ones are real invoices this model must handle, and the
  # fourteen others are the only existing examples of the types it must **refuse** rather than
  # quietly mangle.
  describe "the Ministry's worked examples" do
    it "finds all twenty-six, so a missing pin is not silent" do
      expect(FA3Corpus.ministry.size).to eq(FA3Corpus::MINISTRY_COUNT)
    end

    it "covers every RodzajFaktury the schema defines" do
      types = FA3Corpus.ministry.map { |relative| FA3Corpus.invoice_type(relative) }.uniq

      expect(types).to match_array(Ksef::FA3::Generated::Enums.values_for("TRodzajFaktury"))
    end

    # Our XSD rewriting (§8.3) and validator, against the Ministry's own documents.
    FA3Corpus.ministry.each do |relative|
      it "#{relative} is schema-valid" do
        expect(Ksef::FA3::Validator.errors_for(FA3Corpus.read(relative))).to be_empty
      end
    end

    describe "the eight this model represents" do
      FA3Corpus::MINISTRY_MODELLED.each do |relative|
        it "#{relative} parses and re-serialises to a schema-valid document" do
          parsed = Ksef::FA3.parse(FA3Corpus.read(relative))

          expect(parsed.lines).not_to be_empty
          expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
        end
      end

      # Tier 1 must not reject a real invoice. The absence of exactly this check is what let the
      # whitespace-collapse bug ship: the corpus was asserted against tier 2 only.
      it "all pass validator tier 1" do
        FA3Corpus::MINISTRY_MODELLED.each do |relative|
          expect(Ksef::FA3.parse(FA3Corpus.read(relative)).errors).to be_empty, relative
        end
      end
    end

    # Four VAT invoices that are perfectly valid and beyond this model. Each refusal names the
    # construct and says the document is fine — which is the whole point of refusing rather than
    # parsing them into something lossy.
    describe "the four VAT examples beyond the model" do
      FA3Corpus::MINISTRY_BEYOND_MODEL.each do |relative, reason|
        it "#{relative} is refused, naming the construct" do
          expect { Ksef::FA3.parse(FA3Corpus.read(relative)) }
            .to raise_error(Ksef::ValidationError, reason)
          expect { Ksef::FA3.parse(FA3Corpus.read(relative)) }
            .to raise_error(Ksef::ValidationError, /document itself is fine/)
        end
      end

      it "accounts for every VAT sample, so none is quietly unclassified" do
        vat = FA3Corpus.ministry.select { |r| FA3Corpus.invoice_type(r) == "VAT" }

        expect(vat).to match_array(FA3Corpus::MINISTRY_MODELLED + FA3Corpus::MINISTRY_BEYOND_MODEL.keys)
      end
    end

    # The refusal path, against the documents that motivate it. A KOR carries its corrections in
    # `DaneFaKorygowanej` and its amounts as deltas; parsing one into this model would drop the
    # first and recompute the second, producing a different invoice under the same number.
    describe "the fourteen the model cannot represent" do
      (FA3Corpus.ministry - FA3Corpus::MINISTRY_MODELLED - FA3Corpus::MINISTRY_BEYOND_MODEL.keys)
        .each do |relative|
        it "#{relative} is refused, naming the type and blaming the model" do
          type = FA3Corpus.invoice_type(relative)

          expect { Ksef::FA3.parse(FA3Corpus.read(relative)) }
            .to raise_error(Ksef::ValidationError, /This is a #{type} invoice.*document itself is fine/m)
        end
      end
    end
  end
end
