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

      # "Goldens must validate against the pinned XSD" (CLAUDE.md) was true of these by
      # accident rather than by assertion: `vat_single_line` and `kor_before_after` were
      # validated incidentally by other specs, and `zal_order`, `roz_settlement` and
      # `kor_zal_order` were validated **nowhere**. All six were valid in fact — a missing
      # guard rather than a live defect — and a golden that stops being schema-valid is
      # exactly the regression this suite exists to catch.
      it "#{relative} is schema-valid" do
        expect(Ksef::FA3::Validator.errors_for(sample(relative))).to be_empty
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

  # The Ministry's own twenty-six worked examples (docs/REFERENCE.md §1.5). They are the only
  # examples of the six non-`VAT` types that exist anywhere, and every one of the seven is now
  # modelled — so where this corpus once proved what the parser must **refuse**, it now proves
  # what it must **represent**. Four samples are still beyond the model, all four for a
  # construct rather than a type; see {FA3Corpus::MINISTRY_BEYOND_MODEL}.
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

    describe "the twenty-two this model represents" do
      FA3Corpus::MINISTRY_MODELLED.each do |relative|
        it "#{relative} parses and re-serialises to a schema-valid document" do
          parsed = Ksef::FA3.parse(FA3Corpus.read(relative))

          # `FaWiersz` is `minOccurs="0"`, and a correction of buyer data or a collective
          # discount legitimately has none — but only those, so the exemption is a list.
          if FA3Corpus::MINISTRY_WITHOUT_LINES.include?(relative)
            expect(parsed.lines).to be_empty
          else
            expect(parsed.lines).not_to be_empty
          end
          expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
        end
      end

      # The strong form of the law for the samples that are wholly within the model: parse,
      # serialise, parse again, and get the same object. Weaker than byte-equality — the
      # Ministry writes `-200` where {Ksef::FA3::Formatting.amount} writes `-200.00`, both
      # legal `TKwotowy` — but it is the property DESIGN.md §7.6 actually states, and it is
      # what would have caught a correction losing its `DaneFaKorygowanej` on the way out.
      it "re-parses to an equal invoice, so nothing modelled is lost in a round trip" do
        FA3Corpus::MINISTRY_MODELLED.each do |relative|
          parsed = Ksef::FA3.parse(FA3Corpus.read(relative))

          expect(Ksef::FA3.parse(parsed.to_xml)).to eq(parsed), relative
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

    # With every `RodzajFaktury` modelled, what is left is four invoices refused for a
    # *construct*: two priced gross, two identifying their buyer by something other than a NIP.
    # Each refusal names the construct and says the document is fine, which is the whole point
    # of refusing rather than parsing them into something lossy.
    describe "the four beyond the model — a construct at a time, no longer a type" do
      FA3Corpus::MINISTRY_BEYOND_MODEL.each do |relative, reason|
        it "#{relative} is refused, naming the construct" do
          expect { Ksef::FA3.parse(FA3Corpus.read(relative)) }
            .to raise_error(Ksef::ValidationError, reason)
          expect { Ksef::FA3.parse(FA3Corpus.read(relative)) }
            .to raise_error(Ksef::ValidationError, /document itself is fine/)
        end
      end

      it "accounts for every sample, so none is quietly unclassified" do
        expect(FA3Corpus.ministry)
          .to match_array(FA3Corpus::MINISTRY_MODELLED + FA3Corpus::MINISTRY_BEYOND_MODEL.keys)
      end

      # The no-rows exemption is checked per modelled sample, so an entry that is *not* in the
      # modelled set is never iterated and sits there inert — a bogus path could be added and
      # nothing would fail. The subset is what makes the exemption list mean something.
      it "exempts only samples it actually iterates" do
        expect(FA3Corpus::MINISTRY_WITHOUT_LINES - FA3Corpus::MINISTRY_MODELLED).to be_empty
      end
    end

    # Nothing is refused by type any more. The refusal path itself still exists and still
    # matters — a future FA(4) type, or a schema revision adding one, must not be parsed into
    # a plausible impostor — so it is asserted directly rather than through a sample.
    describe "refusal by type, now unreachable from the corpus" do
      # `expect(MINISTRY_UNSUPPORTED_TYPES).to be_empty` was a literal asserted against its
      # own definition — it passed with `UPR` removed from `SUPPORTED_TYPES`. The constant is
      # now measured: every sample is parsed, and the ones that fail *for their type* are
      # collected. That is the set the constant claims to name, so drift fails here.
      it "leaves no sample refused for its RodzajFaktury" do
        refused = FA3Corpus.ministry.reject do |relative|
          Ksef::FA3.parse(FA3Corpus.read(relative))
          true
        rescue Ksef::ValidationError => e
          !e.message.include?("are modelled so far")
        end

        expect(refused).to eq(FA3Corpus::MINISTRY_UNSUPPORTED_TYPES)
        expect(FA3Corpus.ministry - FA3Corpus::MINISTRY_MODELLED - FA3Corpus::MINISTRY_BEYOND_MODEL.keys)
          .to be_empty
      end

      # The list and the schema must not drift apart: a revision that adds a `RodzajFaktury`
      # should fail here, where the message is about coverage, rather than at runtime.
      it "models every type the schema defines" do
        expect(Ksef::FA3::Parser::SUPPORTED_TYPES)
          .to match_array(Ksef::FA3::Generated::Enums.values_for("TRodzajFaktury"))
      end

      it "still refuses a type the schema does not define, rather than guessing" do
        xml = FA3Corpus.read("mf-samples/przyklad-01.xml").sub("<RodzajFaktury>VAT<", "<RodzajFaktury>FA4<")

        expect { Ksef::FA3.parse(xml) }
          .to raise_error(Ksef::ValidationError, /This is a FA4 invoice.*document itself is fine/m)
      end
    end
  end
end
