# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../tasks/fa3_generator"

# The codegen behind `lib/ksef/fa3/generated/` (DESIGN.md §7.1).
#
# **This file exists because its absence had a measurable cost.** Until 2026-08-26 the extractor
# had no unit spec and was outside SimpleCov entirely, so `method: 100` never applied to it. Its
# only checks were `rake fa3:verify`, which proves *determinism* and not correctness, and
# assertions in `spec/ksef/fa3/generated_spec.rb` about the one schema it happens to read. Three
# defects survived that arrangement, each of which made the generated metadata a false statement
# about the XSD:
#
#   1. attributes read down a descendant axis, so every ancestor claimed its children's;
#   2. anonymous complexTypes nested inside a *named* type were never collected;
#   3. `complexContent` extensions reported no content model at all.
#
# All three are regression-tested below against {synthetic.xsd}, a schema written to contain the
# constructs rather than to look like an invoice. Testing only against FA(3) is what let the
# third one through — FA(3) has exactly one extension, and it is empty.
RSpec.describe Fa3Codegen do
  let(:synthetic_dir) { File.expand_path("../fixtures/codegen", __dir__) }
  let(:synthetic) { File.join(synthetic_dir, "synthetic.xsd") }

  let(:extractor) { Fa3Codegen::Extractor.new(schema_dir: synthetic_dir, main: synthetic) }
  let(:types) { extractor.types }

  describe "content models" do
    # Defect 3. FA(3)'s `Faktura/Podmiot1/AdresKoresp` reported `content: nil` — "takes a text
    # value" — about a type permitting four children, and the serializer turned that into a
    # refusal naming an *empty* list of permitted elements.
    it "resolves a complexContent extension to the base type's model" do
      expect(types.fetch("Faktura/Pusty")[:content][:particles].map { |p| p[:name] })
        .to eq(%w[Podstawowy Opcjonalny])
    end

    it "puts an extension's own particles after the base's" do
      particles = types.fetch("Faktura/Rozszerzony")[:content][:particles]

      expect(particles.flat_map { |p| p[:particles].map { |c| c[:name] } })
        .to eq(%w[Podstawowy Opcjonalny Dodatkowy])
    end

    # Defect 2, in its sharpest form: the anonymous type is reachable only *through* an
    # extension, so a traversal that stops at the extension loses it entirely.
    it "collects an anonymous type declared beneath an extension" do
      expect(types).to have_key("Faktura/Rozszerzony/Dodatkowy")
    end

    # Defect 2. A named type's own anonymous children were never walked, which is why
    # `TNaglowek/KodFormularza` did not exist and `DocumentMapping#header` had to read the
    # attributes one level too high.
    it "keys an anonymous type nested in a named type from the type name" do
      expect(types).to have_key("TNaglowek/Kod")
    end

    it "reports nil content for a simpleContent type, which has text and attributes only" do
      expect(types.fetch("TNaglowek/Kod")[:content]).to be_nil
    end

    # Four FA(3) types have a top-level choice. Unwrapping it would turn "exactly one of these"
    # into "all of these, in order".
    it "preserves a choice as a choice" do
      expect(types.fetch("Faktura/Wybor")[:content][:kind]).to eq(:choice)
    end

    # FA(3) itself declares no `maxOccurs="unbounded"` — measured, zero occurrences — so this
    # branch of `occurs` is dead against the pinned schema and can only be tested here.
    it "records unbounded as nil" do
      particle = types.fetch("Faktura")[:content][:particles].find { |p| p[:name] == "Nieograniczony" }

      expect(particle).to include(max: nil, min: 1)
    end
  end

  describe "attributes" do
    # Defect 1, and the reason it was invisible: the ancestor's answer was *usable*, so the
    # caller got the right values from the wrong place.
    it "attributes an attribute to the type that declares it" do
      expect(types.fetch("TNaglowek/Kod")[:attributes].map { |a| a[:name] })
        .to contain_exactly("tryb", "wersjaSchemy")
    end

    it "does not let an ancestor claim a nested type's attributes" do
      expect(types.fetch("TNaglowek")[:attributes]).to be_empty
      expect(types.fetch("Faktura")[:attributes]).to be_empty
    end

    it "reads an attribute declared on a simpleContent extension" do
      wersja = types.fetch("TNaglowek/Kod")[:attributes].find { |a| a[:name] == "wersjaSchemy" }

      expect(wersja).to eq(name: "wersjaSchemy", type: "xsd:string", use: "required", fixed: "9-9Z")
    end

    it "captures an enumeration declared inline on an attribute" do
      tryb = types.fetch("TNaglowek/Kod")[:attributes].find { |a| a[:name] == "tryb" }

      expect(tryb).to eq(name: "tryb", use: "optional", values: %w[a b])
    end
  end

  # Both were dropped until 2026-08-26, which forced `DocumentMapping` to hand-write
  # `"WariantFormularza" => 3` beneath a comment claiming it came from the metadata.
  describe "element facets" do
    let(:wariant) { types.fetch("Faktura")[:content][:particles].find { |p| p[:name] == "Wariant" } }

    it "captures an inline enumeration on an element" do
      expect(wariant[:values]).to eq(["7"])
    end

    it "captures a fixed value on an element" do
      expect(wariant[:fixed]).to eq("7")
    end
  end

  # Arms that the pinned schema cannot reach, exercised directly rather than left uncovered.
  # An untested arm in a generator is how the three defects above stayed invisible, and
  # "unreachable in FA(3) today" is a statement about one schema, not about the code.
  describe "defensive arms" do
    it "takes an extension's own model when the base is not a named complexType" do
      expect(types.fetch("Faktura/Obcy")[:content][:particles].map { |p| p[:name] }).to eq(["Wlasny"])
    end

    it "collects nothing from an element declared with a named type rather than an anonymous one" do
      collected = {}
      extractor.send(:collect_anonymous, nil, %w[Faktura Nowhere], collected)

      expect(collected).to be_empty
    end

    it "resolves no named type for an absent base" do
      expect(extractor.send(:named_type, nil)).to be_nil
    end
  end

  describe "enums" do
    it "collects named simpleTypes only, which is why inline ones need the facets above" do
      expect(extractor.enums).to eq("TNazwane" => %w[x y])
    end
  end

  describe "schema_version" do
    it "reads the fixed wersjaSchemy attribute" do
      expect(extractor.schema_version).to eq("9-9Z")
    end

    it "raises rather than emitting a header with no version" do
      versionless = Fa3Codegen::Extractor.new(schema_dir: synthetic_dir, main: synthetic)
      allow(versionless).to receive(:schema_version).and_call_original
      doc = versionless.instance_variable_get(:@doc)
      doc.xpath('//xsd:attribute[@name="wersjaSchemy"]', Fa3Codegen::XS).each(&:remove)

      expect { versionless.schema_version }.to raise_error(/wersjaSchemy not found/)
    end
  end

  describe Fa3Codegen::Renderer do
    let(:renderer) { described_class.new(extractor) }

    it "renders valid Ruby that round-trips to the extracted data" do
      Dir.mktmpdir do |dir|
        expect { Fa3Codegen::Generator.new(out_dir: dir, extractor: extractor).generate! }
          .to output(/wrote/).to_stdout

        expect(File.read(File.join(dir, "types.rb"))).to include('"TNaglowek/Kod"')
        expect(File.read(File.join(dir, "enums.rb"))).to include('"TNazwane"')
      end
    end

    # Every key a rendered Hash can hold must be in KEY_ORDER: `sorted_keys` gives unlisted keys
    # one shared rank and `sort_by` is unstable, so two of them tie and the output is
    # nondeterministic. `use` and `fixed` had been tying since attributes were first rendered.
    it "lists every key it can render, so no two tie for one rank" do
      rendered = types.values.flat_map { |meta| meta[:attributes].flat_map(&:keys) } +
                 types.values.filter_map { |meta| meta[:content]&.keys }.flatten +
                 %i[kind name type base min max]

      expect(rendered.uniq - Fa3Codegen::Renderer::KEY_ORDER).to be_empty
    end

    it "renders an empty Hash inline rather than as an empty block" do
      expect(renderer.send(:render, {})).to eq("{}")
      expect(renderer.send(:render, [])).to eq("[]")
    end

    it "leaves a blank line unindented, so trailing whitespace never reaches the output" do
      expect(renderer.send(:indent, "a\n\nb", 2)).to eq("  a\n\n  b")
    end

    it "emits the source SHA-256 so a regenerated file names the schema it came from" do
      expect(renderer.send(:header, "x")).to include(Digest::SHA256.file(synthetic).hexdigest)
    end
  end

  # Moves `rake fa3:verify`'s guarantee into `rspec`, where CI's spec legs see it too: the
  # committed metadata must be exactly what the pinned schema produces.
  it "regenerates the committed metadata byte for byte" do
    drifted, count = described_class.drifted_files

    expect(count).to be_positive
    expect(drifted).to be_empty
  end
end
