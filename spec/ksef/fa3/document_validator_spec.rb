# frozen_string_literal: true

require_relative "../../support/fa3_corpus"

RSpec.describe Ksef::FA3::DocumentValidator do
  let(:golden) { FA3Corpus.read("golden/vat_single_line.xml") }

  def messages(xml, **) = described_class.errors_for(xml, **).map(&:message)

  # Built by codepoint rather than written literally: a control character pasted into a source
  # file is invisible in every diff and review tool that would otherwise catch a typo here.
  def char(codepoint) = codepoint.chr(Encoding::UTF_8)

  def with_text(text) = golden.sub("Consulting", "Consulting#{text}")

  it "passes a document this gem produced" do
    expect(described_class.errors_for(golden)).to be_empty
    expect(described_class.valid?(golden)).to be(true)
  end

  # §15.1's whole point, and not a theoretical one: upstream ships an invoice that is XSD-valid
  # and that KSeF's pinned rules reject.
  describe "the fixture tier 2 provably cannot catch" do
    let(:offending) do
      FA3Corpus.read("ksef-client-csharp/invoice-template-fa-3-with-disallowed-unicode-characters.xml")
    end

    it "is accepted by the schema tier" do
      expect(Ksef::FA3::Validator.errors_for(offending)).to be_empty
    end

    it "is rejected here, naming both characters" do
      expect(messages(offending)).to contain_exactly(
        a_string_matching(/U\+0087/), a_string_matching(/U\+009B/)
      )
    end
  end

  describe "discouraged characters" do
    it "rejects a representative of each forbidden range" do
      [0x7F, 0x84, 0x86, 0x9F, 0xFDD0, 0xFDEF, 0x1FFFE, 0x10FFFF].each do |codepoint|
        expect(messages(with_text(char(codepoint))).size).to eq(1), format("U+%04X", codepoint)
      end
    end

    # U+0085 sits between the first two ranges and is deliberately excluded; the plane
    # noncharacters start at plane 1, because plane 0's are already outside XML's Char
    # production and so cannot occur in a well-formed document at all.
    it "accepts the characters the ranges deliberately exclude" do
      [0x85, 0x20, 0xFDCF, 0xFDF0, 0x41].each do |codepoint|
        expect(described_class.errors_for(with_text(char(codepoint)))).to be_empty,
                                                                          format("U+%04X", codepoint)
      end
    end

    it "reports each distinct character once, however often it occurs" do
      repeated = with_text(char(0x87) * 5)

      expect(messages(repeated).size).to eq(1)
    end

    it "reports two distinct characters separately" do
      expect(messages(with_text(char(0x87) + char(0x9B))).size).to eq(2)
    end
  end

  describe "the byte-order mark" do
    it "rejects a document that starts with one" do
      expect(messages("\xEF\xBB\xBF#{golden}")).to contain_exactly(a_string_matching(/byte-order mark/))
    end
  end

  describe "the prolog" do
    it "rejects an encoding that is not UTF-8" do
      expect(messages(golden.sub('encoding="UTF-8"', 'encoding="ISO-8859-2"')))
        .to contain_exactly(a_string_matching(/declares encoding "ISO-8859-2"/))
    end

    it "accepts UTF-8 in any case, since the comparison is not case-sensitive" do
      expect(described_class.errors_for(golden.sub('encoding="UTF-8"', "encoding='utf-8'"))).to be_empty
    end

    # The prolog is optional; only its content is constrained.
    it "accepts a document with no prolog at all" do
      expect(described_class.errors_for(golden.sub(/\A<\?xml[^>]*\?>\n?/, ""))).to be_empty
    end

    it "accepts a prolog that declares no encoding" do
      expect(described_class.errors_for(golden.sub(/\A<\?xml[^>]*\?>/, '<?xml version="1.0"?>'))).to be_empty
    end
  end

  describe "processing instructions" do
    it "rejects one, naming its target" do
      instructed = golden.sub("<Faktura", %(<?xml-stylesheet href="x"?>\n<Faktura))

      expect(messages(instructed)).to contain_exactly(a_string_matching(/xml-stylesheet/))
    end

    # The XML declaration looks like a processing instruction and is not one; mistaking them
    # would reject every document this gem writes.
    it "does not mistake the declaration for one" do
      expect(described_class.errors_for(golden)).to be_empty
    end
  end

  describe "size" do
    it "rejects a document past the million-byte ceiling" do
      oversized = with_text("C" * 1_000_000)

      expect(messages(oversized)).to include(a_string_matching(/KSeF accepts 1000000/))
    end

    # Upstream writes "1 MB * (1 000 000 bajtów)" — the decimal million, not 2^20.
    #
    # This example previously used `"ż" * 400_000` — 400k characters, 800k bytes, under the
    # limit on *either* reading, so it distinguished nothing and a `bytesize` → `length`
    # mutation survived the whole suite. 600k two-byte characters is 1.2 MB of bytes and 600k
    # characters, which only a byte measurement rejects.
    it "measures bytes rather than characters" do
      expect(described_class::MAX_BYTES).to eq(1_000_000)
      expect(messages("ż" * 600_000)).to include(a_string_matching(/is 1200000 bytes/))
      expect(described_class.errors_for("ż" * 400_000)).to be_empty
    end

    # "Maksymalny rozmiar" is inclusive, and the analogous boundary is pinned for text lengths.
    it "accepts a document of exactly the ceiling and rejects one byte more" do
      expect(described_class.errors_for("a" * 1_000_000)).to be_empty
      expect(messages("a" * 1_000_001)).to include(a_string_matching(/is 1000001 bytes/))
    end

    # The figure is a *default*: upstream's asterisk says an organisation can have it raised,
    # and `limity.md` heads the same numbers "Wartość domyślna" (docs/REFERENCE.md §15.5).
    it "honours a negotiated ceiling" do
      expect(described_class.errors_for("a" * 2_000_000, max_bytes: 3_000_000)).to be_empty
      expect(messages("a" * 100, max_bytes: 50)).to include(a_string_matching(/accepts 50/))
    end
  end

  describe "the second half of the encoding rule" do
    # Upstream says "musi być kodowana w UTF-8 bez znaku BOM" — encoded in UTF-8 *and* without a
    # BOM. Only the BOM was checked, and invalid bytes crashed the scan instead of reporting.
    it "rejects bytes that are not valid UTF-8, rather than raising" do
      expect(messages("<Faktura>\xFF</Faktura>".dup.force_encoding("UTF-8")))
        .to contain_exactly(a_string_matching(/not valid UTF-8/))
    end

    it "reports it as the only issue, since nothing else can be read from the bytes" do
      expect(described_class.errors_for("\xFF\xFE".dup.force_encoding("UTF-8")).size).to eq(1)
    end
  end

  describe "#valid?" do
    it "is false for a document KSeF would refuse" do
      expect(described_class.valid?("\xEF\xBB\xBF#{golden}")).to be(false)
    end

    it "forwards a negotiated ceiling" do
      expect(described_class.valid?(golden, max_bytes: 10)).to be(false)
    end
  end

  describe "processing instructions that are only text" do
    # `<?php ... ?>` inside a comment or CDATA is text, not an instruction; rejecting it would
    # refuse an admissible document.
    it "ignores one inside a comment" do
      expect(described_class.errors_for(golden.sub("<Faktura", "<!-- <?php gen ?> -->\n<Faktura")))
        .to be_empty
    end

    it "ignores one inside CDATA" do
      cdata = golden.sub("Consulting", "<![CDATA[<?php gen ?>]]>")

      expect(described_class.errors_for(cdata)).to be_empty
    end

    # A PI target is an XML Name and may hold non-ASCII letters; an ASCII-only class waved this
    # through, and it was the one input every tier passed while §15.1 says KSeF rejects it.
    it "catches a target that is not ASCII" do
      expect(messages(golden.sub("<Faktura", "<?źdźbło x?>\n<Faktura")))
        .to contain_exactly(a_string_matching(/źdźbło/))
    end
  end
end
