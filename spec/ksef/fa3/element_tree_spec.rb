# frozen_string_literal: true

RSpec.describe Ksef::FA3::ElementTree do
  def node(xml) = Nokogiri::XML("<root>#{xml}</root>").root

  describe ".to_hash" do
    it "reads a leaf as its text" do
      expect(described_class.to_hash(node("<P_16>1</P_16>"))).to eq("P_16" => "1")
    end

    it "reads a parent as a nested Hash" do
      expect(described_class.to_hash(node("<Zwolnienie><P_19>1</P_19></Zwolnienie>")))
        .to eq("Zwolnienie" => { "P_19" => "1" })
    end

    it "nests to any depth" do
      expect(described_class.to_hash(node("<a><b><c>x</c></b></a>")))
        .to eq("a" => { "b" => { "c" => "x" } })
    end

    # The shape {Ksef::FA3::Serializer} writes for a repeated element is an Array, so that is
    # what a repeated name has to read back as.
    it "collects a repeated leaf into an Array" do
      expect(described_class.to_hash(node("<x>1</x><x>2</x>"))).to eq("x" => %w[1 2])
    end

    it "keeps collecting past the second occurrence" do
      expect(described_class.to_hash(node("<x>1</x><x>2</x><x>3</x>"))).to eq("x" => %w[1 2 3])
    end

    # `Array()` would splat a Hash into an array of pairs, quietly mangling a repeated parent
    # into nonsense — which is why the append is written out by hand.
    it "collects repeated parents without flattening them into pairs" do
      expect(described_class.to_hash(node("<p><q>1</q></p><p><q>2</q></p>")))
        .to eq("p" => [{ "q" => "1" }, { "q" => "2" }])
    end

    it "returns nil for an absent node, so a caller's default can apply" do
      expect(described_class.to_hash(nil)).to be_nil
    end

    it "returns an empty Hash for an element with no children" do
      expect(described_class.to_hash(node(""))).to eq({})
    end

    # Text mixed with elements is not something FA(3) produces, but it must not silently
    # swallow the elements if it ever appears.
    it "ignores text alongside child elements" do
      expect(described_class.to_hash(node("<a>stray<b>1</b></a>"))).to eq("a" => { "b" => "1" })
    end
  end

  # The round trip that matters: whatever this reads, the serializer must be able to write.
  describe "feeding the serializer" do
    it "reproduces an annotations block it read" do
      xml = <<~XML
        <Adnotacje><P_16>1</P_16><P_17>2</P_17><P_18>2</P_18><P_18A>2</P_18A>
        <Zwolnienie><P_19>1</P_19><P_19A>art. 43</P_19A></Zwolnienie>
        <NoweSrodkiTransportu><P_22N>1</P_22N></NoweSrodkiTransportu>
        <P_23>2</P_23><PMarzy><P_PMarzyN>1</P_PMarzyN></PMarzy></Adnotacje>
      XML
      read = described_class.to_hash(Nokogiri::XML(xml).root)

      expect(read["P_16"]).to eq("1")
      expect(read["Zwolnienie"]).to eq("P_19" => "1", "P_19A" => "art. 43")
    end
  end
end
