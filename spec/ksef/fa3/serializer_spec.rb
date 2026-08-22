# frozen_string_literal: true

RSpec.describe Ksef::FA3::Serializer do
  def render(content) = Nokogiri::XML(described_class.new(content).to_xml).remove_namespaces!

  describe "ordering" do
    # The point of the whole design: callers describe what the invoice contains, the
    # schema decides where each part goes. KSeF rejects out-of-order elements.
    it "reorders input into schema order" do
      scrambled = { "Fa" => { "P_15" => "1.00", "KodWaluty" => "PLN", "P_2" => "X", "P_1" => "2026-08-22" } }

      expect(render(scrambled).xpath("//Fa/*").map(&:name)).to eq(%w[KodWaluty P_1 P_2 P_15])
    end

    it "ignores the order of the input hash entirely" do
      forwards = { "Fa" => { "KodWaluty" => "PLN", "P_2" => "X" } }
      backwards = { "Fa" => { "P_2" => "X", "KodWaluty" => "PLN" } }

      expect(described_class.new(forwards).to_xml).to eq(described_class.new(backwards).to_xml)
    end
  end

  describe "structure" do
    it "emits a repeated element once per array member, in order" do
      content = { "Fa" => { "FaWiersz" => [{ "NrWierszaFa" => 1 }, { "NrWierszaFa" => 2 }] } }
      rows = render(content).xpath("//FaWiersz/NrWierszaFa").map(&:text)

      expect(rows).to eq(%w[1 2])
    end

    it "treats a Hash as one nested element rather than a list" do
      expect(render({ "Naglowek" => { "WariantFormularza" => 3 } }).xpath("//Naglowek").size).to eq(1)
    end

    it "skips an element whose value is nil" do
      content = { "Podmiot1" => { "Adres" => nil, "DaneIdentyfikacyjne" => { "Nazwa" => "X" } } }
      rendered = render(content)

      expect(rendered.at_xpath("//Podmiot1/Adres")).not_to be_nil
      expect(rendered.at_xpath("//Podmiot1/Adres").element_children).to be_empty
    end

    it "qualifies every element, not just the root" do
      document = Nokogiri::XML(described_class.new({ "Fa" => { "KodWaluty" => "PLN" } }).to_xml)
      namespaces = document.xpath("//*").map { |n| n.namespace&.href }.uniq

      expect(namespaces).to eq([described_class::NAMESPACE])
    end

    it "declares UTF-8 and round-trips Polish characters" do
      xml = described_class.new({ "Fa" => { "P_2" => "Faktura Żółć" } }).to_xml

      expect(xml).to start_with(%(<?xml version="1.0" encoding="UTF-8"?>))
      expect(render({ "Fa" => { "P_2" => "Faktura Żółć" } }).at_xpath("//P_2").text).to eq("Faktura Żółć")
    end
  end

  describe described_class::Element do
    it "writes attributes alongside text" do
      content = { "Naglowek" => { "KodFormularza" => described_class.new(text: "FA", attributes: { "a" => "b" }) } }
      node = Nokogiri::XML(Ksef::FA3::Serializer.new(content).to_xml).remove_namespaces!.at_xpath("//KodFormularza")

      expect(node.text).to eq("FA")
      expect(node["a"]).to eq("b")
    end

    it "writes an attributes-only element with no text" do
      content = { "Naglowek" => { "KodFormularza" => described_class.new(attributes: { "a" => "b" }) } }
      node = Nokogiri::XML(Ksef::FA3::Serializer.new(content).to_xml).remove_namespaces!.at_xpath("//KodFormularza")

      expect(node.text).to eq("")
      expect(node["a"]).to eq("b")
    end
  end

  # A mistyped element name would otherwise produce a document silently missing a field —
  # which the schema might still accept if the field was optional.
  describe "unknown keys" do
    it "raises rather than dropping them" do
      expect { described_class.new({ "Naglowek" => { "Typo" => "x" } }).to_xml }
        .to raise_error(Ksef::ValidationError, /Unknown element\(s\) "Typo" for TNaglowek/)
    end

    it "lists what is permitted there, in schema order" do
      expect { described_class.new({ "Naglowek" => { "Typo" => "x" } }).to_xml }
        .to raise_error(Ksef::ValidationError, /KodFormularza, WariantFormularza, DataWytworzeniaFa/)
    end

    it "catches an unknown key nested deep in the document" do
      expect { described_class.new({ "Fa" => { "FaWiersz" => [{ "Nope" => 1 }] } }).to_xml }
        .to raise_error(Ksef::ValidationError, /Unknown element\(s\) "Nope"/)
    end
  end

  describe "type resolution" do
    it "resolves a named type by name" do
      # Naglowek is tns:TNaglowek — a named complexType.
      rendered = render({ "Naglowek" => { "WariantFormularza" => 3 } })
      expect(rendered.at_xpath("//Naglowek/WariantFormularza")).not_to be_nil
    end

    it "resolves an anonymous type by its element path" do
      # Podmiot1 has an inline complexType, keyed "Faktura/Podmiot1".
      content = { "Podmiot1" => { "DaneIdentyfikacyjne" => { "Nazwa" => "ACME" } } }
      expect(render(content).at_xpath("//Podmiot1/DaneIdentyfikacyjne/Nazwa").text).to eq("ACME")
    end
  end
end
