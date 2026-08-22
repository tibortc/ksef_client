# frozen_string_literal: true

RSpec.describe Ksef::FA3::Validator do
  let(:valid_xml) do
    File.read(File.expand_path("../../fixtures/fa3/minimal_vat_invoice.xml", __dir__), encoding: "UTF-8")
  end

  describe "offline compilation" do
    # The shipped XSD imports http://crd.gov.pl/… — compiling it unmodified makes libxml2
    # fetch that at validation time. The suite forbids network access, and an air-gapped
    # deployment would hang or fail, so the import is redirected in memory.
    it "leaves no remote schemaLocation in the compiled document" do
      document = described_class.send(:rewritten_schema_document)
      locations = document.xpath("//*[local-name()='import']").map { |i| i["schemaLocation"] }

      expect(locations).not_to be_empty
      expect(locations).to all(start_with(described_class::BASE_SCHEMA_DIR))
    end

    it "does not modify the pinned file on disk, so its recorded digest still verifies" do
      before = File.read(described_class::MAIN_SCHEMA, encoding: "UTF-8")
      described_class.errors_for(valid_xml)
      expect(File.read(described_class::MAIN_SCHEMA, encoding: "UTF-8")).to eq(before)
    end

    it "compiles a usable schema" do
      expect(described_class.schema).to be_a(Nokogiri::XML::Schema)
    end

    it "memoises the compiled schema, which is expensive to build" do
      first_call = described_class.schema
      expect(described_class.schema).to be(first_call)
    end
  end

  describe "a conforming invoice" do
    it "validates" do
      expect(described_class.errors_for(valid_xml)).to be_empty
      expect(described_class.valid?(valid_xml)).to be(true)
    end

    it "accepts a pre-parsed document as well as a string" do
      expect(described_class.valid?(Nokogiri::XML(valid_xml))).to be(true)
    end

    it "round-trips Polish characters" do
      expect(valid_xml).to include("Długa", "Kraków")
    end

    it "passes validate! without raising" do
      expect(described_class.validate!(valid_xml)).to be(true)
    end
  end

  describe "rejections" do
    it "catches a missing required element" do
      broken = valid_xml.sub(%r{<P_2>.*?</P_2>\n\s*}, "")
      expect(described_class.valid?(broken)).to be(false)
    end

    # The reason the codegen preserves ordering at all: KSeF rejects out-of-order
    # elements, and so does the schema.
    it "catches elements in the wrong order" do
      swapped = valid_xml.sub(%r{(\s*<P_1>[^<]*</P_1>)(\s*<P_2>[^<]*</P_2>)}) do
        "#{Regexp.last_match(2)}#{Regexp.last_match(1)}"
      end

      expect(swapped).not_to eq(valid_xml)
      expect(described_class.valid?(swapped)).to be(false)
    end

    it "catches a value outside an enumeration" do
      expect(described_class.valid?(valid_xml.sub("<P_12>23</P_12>", "<P_12>99</P_12>"))).to be(false)
    end

    it "catches a wrong fixed attribute" do
      expect(described_class.valid?(valid_xml.sub('wersjaSchemy="1-0E"', 'wersjaSchemy="9-9Z"'))).to be(false)
    end

    it "raises ValidationError from validate!, listing the violations" do
      broken = valid_xml.sub("<P_12>23</P_12>", "<P_12>99</P_12>")
      expect { described_class.validate!(broken) }
        .to raise_error(Ksef::ValidationError, /does not conform to the FA\(3\) schema/)
    end
  end

  # Recorded in docs/REFERENCE.md §8.2. Genuinely surprising, and the schema is the only
  # place it is stated: an invoice is invalid without them.
  describe "the mandatory buyer flags" do
    it "requires JST on Podmiot2" do
      without = valid_xml.sub(%r{\s*<JST>\d</JST>}, "")
      expect(described_class.valid?(without)).to be(false)
    end

    it "requires GV on Podmiot2" do
      without = valid_xml.sub(%r{\s*<GV>\d</GV>}, "")
      expect(described_class.valid?(without)).to be(false)
    end

    it "accepts only 1 or 2, per etd:TWybor1_2" do
      expect(described_class.valid?(valid_xml.sub("<JST>2</JST>", "<JST>3</JST>"))).to be(false)
    end
  end
end
