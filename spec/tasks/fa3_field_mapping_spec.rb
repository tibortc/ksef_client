# frozen_string_literal: true

require_relative "../../tasks/field_mapping"

# The generator behind `docs/field_mapping.md` (DESIGN.md §7.2).
#
# What is worth testing here is not the Markdown — `rake fa3:verify` already fails if the
# committed file is stale, so the rendering is pinned byte-for-byte by the build. It is the
# **three drift guards**: the whole reason §7.2 insists the table be generated from a declared
# mapping is that a hand-written one goes quietly out of date, and a generator that failed
# silently would be no better.
RSpec.describe Fa3FieldMapping do
  let(:schema) { described_class::Schema.new }

  describe "resolving a declared path against the pinned schema" do
    it "reads an element's type and cardinality" do
      expect(schema.particle("Faktura/Fa/P_2")).to include(name: "P_2", type: "tns:TZnakowy", min: 1, max: 1)
    end

    it "walks into a named complexType" do
      expect(schema.particle("Faktura/Podmiot2/DaneIdentyfikacyjne/NIP")).to include(name: "NIP")
    end

    it "walks into an anonymous one, which is most of FA(3)" do
      expect(schema.particle("Faktura/Fa/FaWiersz/P_7")).to include(name: "P_7", min: 0)
    end

    # Guard 1. A schema revision that renames or removes an element must break the build here,
    # where the message names the path, rather than produce a table that quietly lies.
    it "refuses a path the schema does not have" do
      expect { schema.particle("Faktura/Fa/P_999") }
        .to raise_error(RuntimeError, %r{Faktura/Fa/P_999: no element "P_999" under "Faktura/Fa"})
    end

    it "refuses a path that turns off the schema partway" do
      expect { schema.particle("Faktura/Fa/P_2/Nonsense") }.to raise_error(RuntimeError, /no element/)
    end
  end

  describe "the Ministry's descriptions" do
    it "reads the annotation verbatim where every occurrence of the name agrees" do
      expect(schema.documentation("P_1")).to eq("Data wystawienia, z zastrzeżeniem art. 106na ust. 1 ustawy")
    end

    # Eleven names are declared more than once with *different* wording — `DaneIdentyfikacyjne`
    # has five variants, `Adres` four. There is no single answer for those, and guessing one
    # would put the wrong statute against a field an auditor is reading.
    it "answers nil for a name whose occurrences disagree" do
      expect(schema.documentation("Adres")).to be_nil
      expect(schema.documentation("DaneIdentyfikacyjne")).to be_nil
    end

    it "still answers for a name repeated with identical wording" do
      expect(schema.documentation("NIP")).to eq("Identyfikator podatkowy NIP")
    end

    it "truncates a description too long for a table cell, on a sentence boundary" do
      expect(schema.documentation("FaWiersz")).to end_with(" […]")
      expect(schema.documentation("FaWiersz").length).to be <= 230
    end

    it "reads the schema version the same way the codegen does" do
      expect(schema.version).to eq("1-0E")
    end

    # The codegen raises on the same absence for the same reason: a schema whose shape has
    # changed enough to lose this attribute needs a human, not a best guess.
    it "refuses a schema with no wersjaSchemy, rather than labelling the table with nothing" do
      allow(File).to receive(:read).and_return('<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"/>')

      expect { described_class::Schema.new.version }
        .to raise_error(RuntimeError, /wersjaSchemy not found/)
    end
  end

  describe "the declared mapping" do
    # Guard 2 and guard 3, which are what stop the table falling behind the *model*.
    it "declares every member of every model it covers" do
      described_class::MODELS.each do |model|
        klass = Object.const_get(model[:model])
        declared = model[:fields].map(&:first).map(&:to_sym)

        expect(declared).to match_array(klass.members), model[:model]
      end
    end

    it "gives every unmapped attribute a reason" do
      described_class::MODELS.each do |model|
        model[:fields].filter_map { |attribute, path| attribute if path.nil? }.each do |attribute|
          expect(described_class::UNMAPPED).to have_key("#{model[:model].split("::").last}##{attribute}")
        end
      end
    end

    it "leaves no UNMAPPED entry that nothing refers to" do
      referenced = described_class::MODELS.flat_map do |model|
        model[:fields].filter_map do |attribute, path|
          "#{model[:model].split("::").last}##{attribute}" if path.nil?
        end
      end

      expect(described_class::UNMAPPED.keys).to match_array(referenced)
    end

    it "resolves every declared path" do
      paths = described_class::MODELS.flat_map { |model| model[:fields].map(&:last) }.compact

      expect { paths.each { |path| schema.particle(path) } }.not_to raise_error
    end
  end

  describe "rendering" do
    let(:rendered) { described_class::Renderer.new(schema: schema).render }

    it "matches the committed document, so a stale file fails the build" do
      expect(rendered).to eq(File.read(described_class::OUT, encoding: "UTF-8"))
    end

    it "names an anonymous complexType as inline rather than inventing a name for it" do
      expect(rendered).to include("| `seller` | `Podmiot1` | *(inline)* |")
    end

    it "reports the three buckets no rate code reaches" do
      %w[P_13_5 P_14_5 P_13_11].each do |element|
        expect(rendered).to include("| `#{element}` | *(no rate code reaches it)*"), element
      end
    end

    it "lists the rate codes that share a bucket, since the map is not invertible" do
      expect(rendered).to include("| `P_13_1` | `23`, `22` |")
    end

    it "aborts on a declared attribute the model does not have" do
      broken = [{ model: "Ksef::FA3::Address", title: "t", intro: "i",
                  fields: [%w[line1 Faktura/Podmiot2/Adres/AdresL1], %w[nonsense Faktura/Fa/P_2]] }]
      stub_const("#{described_class}::MODELS", broken)

      expect { described_class::Renderer.new(schema: schema).render }
        .to raise_error(RuntimeError, /declared but not a member: \[:nonsense\]/)
    end

    it "aborts on a model member nobody declared" do
      broken = [{ model: "Ksef::FA3::Address", title: "t", intro: "i",
                  fields: [%w[line1 Faktura/Podmiot2/Adres/AdresL1]] }]
      stub_const("#{described_class}::MODELS", broken)

      expect { described_class::Renderer.new(schema: schema).render }
        .to raise_error(RuntimeError, /neither mapped nor in UNMAPPED: \[:line2, :country\]/)
    end

    it "aborts on a nil path with no reason given" do
      broken = [{ model: "Ksef::FA3::Address", title: "t", intro: "i",
                  fields: [["line1", nil], %w[line2 Faktura/Podmiot2/Adres/AdresL2],
                           %w[country Faktura/Podmiot2/Adres/KodKraju]] }]
      stub_const("#{described_class}::MODELS", broken)

      expect { described_class::Renderer.new(schema: schema).render }
        .to raise_error(RuntimeError, /Address#line1 has a nil path and no UNMAPPED entry/)
    end
  end

  # This is the gate `rake fa3:verify` runs, and therefore the gate `rake` runs — so the
  # committed document cannot fall behind the declaration or the schema without CI going red.
  describe ".stale?" do
    it "is false when the committed document is what a fresh run produces" do
      expect(described_class).not_to be_stale
    end

    it "is true when it is not" do
      original = File.read(described_class::OUT, encoding: "UTF-8")
      File.write(described_class::OUT, "#{original}\nedited by hand\n", encoding: "UTF-8")

      expect(described_class).to be_stale
    ensure
      File.write(described_class::OUT, original, encoding: "UTF-8")
    end
  end

  describe ".generate!" do
    it "writes the document" do
      allow(File).to receive(:write)
      described_class.generate!

      expect(File).to have_received(:write).with(described_class::OUT, kind_of(String), encoding: "UTF-8")
    end
  end
end
