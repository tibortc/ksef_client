# frozen_string_literal: true

require_relative "../../tasks/field_mapping"
require_relative "../support/fa3_corpus"

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
      expect(schema.field("Faktura/Fa/P_2"))
        .to include(name: "P_2", type: "tns:TZnakowy", occurs: { min: 1, max: 1, choice: false })
    end

    it "walks into a named complexType" do
      expect(schema.field("Faktura/Podmiot2/DaneIdentyfikacyjne/NIP"))
        .to include(name: "NIP", occurs: { min: 0, max: 1, choice: true })
    end

    it "walks into an anonymous one, which is most of FA(3)" do
      expect(schema.field("Faktura/Fa/FaWiersz/P_7")).to include(name: "P_7")
    end

    # Guard 1. A schema revision that renames or removes an element must break the build here,
    # where the message names the path, rather than produce a table that quietly lies.
    it "refuses a path the schema does not have" do
      expect { schema.field("Faktura/Fa/P_999") }
        .to raise_error(RuntimeError, %r{Faktura/Fa/P_999: no element "P_999" under "Fa"})
    end

    it "refuses a root element the schema does not declare" do
      expect { schema.field("Fakturka/Fa/P_2") }
        .to raise_error(RuntimeError, /no root element "Fakturka"/)
    end

    # FA(3) declares no unbounded element — `maxOccurs="unbounded"` appears zero times — so
    # this cannot fire today. It raises rather than rendering a dangling bound, because a
    # schema revision that introduced one would otherwise print `0–` and look merely odd.
    it "refuses an unbounded element rather than rendering half a bound" do
      unbounded = Nokogiri::XML(<<~XSD)
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:element name="Faktura"><xsd:complexType><xsd:sequence>
            <xsd:element name="Wiele" type="xsd:string" maxOccurs="unbounded"/>
          </xsd:sequence></xsd:complexType></xsd:element>
        </xsd:schema>
      XSD
      allow(File).to receive(:read).and_return(unbounded.to_xml)

      expect { described_class::Schema.new.field("Faktura/Wiele") }
        .to raise_error(RuntimeError, /unbounded maxOccurs/)
    end

    it "refuses a path that turns off the schema partway" do
      expect { schema.field("Faktura/Fa/P_2/Nonsense") }.to raise_error(RuntimeError, /no element/)
    end
  end

  describe "the Ministry's descriptions" do
    it "reads the annotation verbatim, and does not abridge it" do
      expect(schema.field("Faktura/Fa/P_1")[:documentation])
        .to eq("Data wystawienia, z zastrzeżeniem art. 106na ust. 1 ustawy")
    end

    # The first version looked descriptions up by bare element **name**, so any name declared
    # more than once with different wording had to be dropped — `Adres` and `KodKraju` came
    # back blank. Eleven names are ambiguous that way; resolving the path removes the question,
    # and `Adres`'s buyer-context text is exactly the buyer/seller asymmetry worth surfacing.
    it "is path-exact, so a name declared several ways is still answered" do
      expect(schema.field("Faktura/Podmiot2/Adres")[:documentation])
        .to eq("Adres nabywcy. Pola opcjonalne dla przypadków określonych w art. 106e ust. 5 pkt 3 ustawy")
      expect(schema.field("Faktura/Podmiot1/Adres")[:documentation]).to eq("Adres podatnika")
    end

    # Truncation cut mid-citation, because every Polish statutory abbreviation ends in ". " —
    # rows terminated at "o której mowa w art. 106j ust. […]". Worse, it dropped the
    # "W przypadku faktur korygujących" clause from ten of the eighteen summary buckets, which
    # is where a correction's amounts are defined as deltas.
    it "keeps the clause that makes a correction's figures deltas" do
      expect(schema.field("Faktura/Fa/P_15")[:documentation])
        .to include("W przypadku faktur korygujących - korekta kwoty wynikającej z faktury korygowanej")
      expect(schema.field("Faktura/Fa/P_14_1")[:documentation]).to include("kwota różnicy")
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

  describe "effective cardinality" do
    # The reason the resolver walks the XSD rather than reading `Generated::Types`: that table
    # is flattened for the serializer's benefit, so it reports a choice branch and an element
    # inside an optional sequence as mandatory. The buyer's name is the case §8.2a records as
    # having bitten this project three times.
    it "reports a buyer's name as optional and a seller's as required" do
      expect(schema.field("Faktura/Podmiot2/DaneIdentyfikacyjne/Nazwa")[:occurs]).to include(min: 0)
      expect(schema.field("Faktura/Podmiot1/DaneIdentyfikacyjne/Nazwa")[:occurs]).to include(min: 1)
    end

    it "reports a choice branch as a choice rather than as required" do
      expect(schema.field("Faktura/Fa/FakturaZaliczkowa/NrFaZaliczkowej")[:occurs]).to include(choice: true)
    end

    it "reports an element inside an optional sequence as optional" do
      expect(schema.field("Faktura/Fa/P_15ZK")[:occurs]).to include(min: 0)
    end
  end

  # **The guard the first version did not have.** Path resolution and member checks prove both
  # ends of a mapping exist; neither proves they *correspond*. Swapping `number → P_1` with
  # `issue_date → P_2` passed every guard and rendered a table stating, under the Ministry's own
  # annotations, that `number` means "Data wystawienia". This checks the pairing against real
  # documents, which is the one claim the whole file exists to make.
  #
  # Scoped to `Invoice`'s own scalar fields: they are the most-read section, and the deeper
  # models are already pinned element-for-element by DESIGN.md §7.6's round-trip law over the
  # same corpus. Say so rather than implying wider coverage than this has.
  describe "the attribute↔element pairing, against the Ministry's documents" do
    def scalars
      { "number" => "P_2", "issue_date" => "P_1", "currency" => "KodWaluty",
        "invoice_type" => "RodzajFaktury" }
    end

    it "declares the pairing the documents actually use" do
      declared = described_class::MODELS
                 .find { |model| model[:model] == "Ksef::FA3::Invoice" }[:fields]
                 .to_h { |attribute, path| [attribute, path&.split("/")&.last] }

      expect(declared.slice(*scalars.keys)).to eq(scalars)
    end

    FA3Corpus::MINISTRY_MODELLED.each do |relative|
      it "#{relative} carries each value in the element the table names" do
        source = FA3Corpus.read(relative)
        invoice = Ksef::FA3.parse(source)
        document = Nokogiri::XML(source).remove_namespaces!

        scalars.each do |attribute, element|
          expect(document.at_xpath("//Fa/#{element}").text.strip)
            .to eq(invoice.public_send(attribute).to_s), "#{attribute} vs #{element}"
        end
      end
    end
  end

  describe "the declared mapping" do
    # Guard 5, in the spec rather than the generator: a value object nobody listed is a whole
    # model missing from the table, and the generator has no notion of which classes ought to
    # be there. `Issue` is a validator diagnostic and `Serializer::Element` is internal
    # plumbing; neither carries invoice fields.
    it "covers every value object that carries invoice fields" do
      value_objects = Ksef::FA3.constants.map { |name| Ksef::FA3.const_get(name) }
                               .select { |const| const.is_a?(Class) && const < Data }
                               .map(&:name).sort

      # `Issue` is a validator diagnostic and `Serializer::Element` internal plumbing; neither
      # carries invoice fields.
      expect(value_objects - %w[Ksef::FA3::Issue Ksef::FA3::Serializer::Element])
        .to match_array(described_class::MODELS.map { |model| model[:model] }.uniq)
    end

    # Guard 2 and guard 3, which are what stop the table falling behind the *model*.
    it "declares every member of every model it covers" do
      described_class::MODELS.each do |model|
        klass = Object.const_get(model[:model])
        declared = model[:fields].map(&:first).map(&:to_sym)

        expect(declared).to match_array(klass.members), model[:model]
      end
    end

    it "gives every unmapped attribute a reason, and leaves no reason orphaned" do
      referenced = described_class::MODELS.flat_map do |model|
        prefix = model[:key] || model[:model].split("::").last
        model[:fields].filter_map { |attribute, path| "#{prefix}##{attribute}" if path.nil? }
      end

      expect(described_class::UNMAPPED.keys).to match_array(referenced)
    end

    it "aborts on an UNMAPPED entry nothing refers to" do
      stub_const("#{described_class}::UNMAPPED",
                 described_class::UNMAPPED.merge("Address#ghost" => { element: nil, why: "x" }))

      expect { described_class::Renderer.new(schema: schema).render }
        .to raise_error(RuntimeError, /UNMAPPED entries nothing refers to: \["Address#ghost"\]/)
    end

    it "resolves every declared path" do
      paths = described_class::MODELS.flat_map { |model| model[:fields].map { |field| field[1] } }.compact

      expect { paths.each { |path| schema.field(path) } }.not_to raise_error
    end
  end

  describe "rendering" do
    let(:rendered) { described_class::Renderer.new(schema: schema).render }

    def index_of(document) = document[/## Element index.*/m]

    it "matches the committed document, so a stale file fails the build" do
      expect(rendered).to eq(File.read(described_class::OUT, encoding: "UTF-8"))
    end

    it "names an anonymous complexType as inline rather than inventing a name for it" do
      expect(rendered).to include("| `seller` | `Podmiot1` | *(inline)* |")
    end

    it "reports the three buckets no rate code reaches" do
      %w[P_13_5 P_14_5 P_13_11].each do |element|
        expect(rendered).to include("| `#{element}` | *(none)*"), element
      end
    end

    # DESIGN.md §11 makes determinism a definition-of-done gate for codegen, and this file is
    # generated under the same gate. It failed once: the element index sorted on the element
    # name alone, `sort_by` is not stable, and three names appear twice — so the tie order came
    # out one way on macOS and the other on Linux. Green locally, stale in CI.
    # **`before` is captured ahead of the stub, and that is the whole example.** It used to
    # reference the `rendered` `let` inside the `expect`, i.e. after `stub_const` had already
    # replaced `MODELS` — so both sides were the shuffled render and it passed with the
    # determinism bug reintroduced. Mutation testing found it comparing a value to itself.
    it "renders identically from a shuffled declaration, so ties are not left to sort order" do
      before = rendered
      shuffled = described_class::MODELS.map { |model| model.merge(fields: model[:fields].reverse) }
      stub_const("#{described_class}::MODELS", shuffled)

      # Scoped to the element index: reversing the declaration legitimately reorders rows
      # within each model's own table, which is declaration order and not a tie. The index is
      # the section that sorts, and therefore the only one where a tie can be resolved twice.
      expect(index_of(described_class::Renderer.new(schema: schema).render)).to eq(index_of(before))
    end

    # The path is `fields[1]`, never `.last`, because a row may carry a third element — its
    # English note. Benign today only by coincidence: every three-element row's path segments
    # happen to be contributed by some two-element row as well. Add a note to the row that
    # uniquely carries a segment and the negative list would gain `KodWaluty`, telling an
    # auditor the model does not carry the invoice currency two rows below where it maps it.
    it "reads the path from fields[1], so a note is never taken for a path" do
      before = rendered
      noted = described_class::MODELS.map do |model|
        model.merge(fields: model[:fields].map { |attribute, path, *| [attribute, path, "a note"] })
      end
      stub_const("#{described_class}::MODELS", noted)

      expect(described_class::Renderer.new(schema: schema).render.lines.grep(/^\| `Faktura/))
        .to eq(before.lines.grep(/^\| `Faktura/))
    end

    # One language per column: the Ministry's own text in one, ours in the other. The first
    # version put our English notes into the column headed "The Ministry's description", so a
    # reader met two languages under one heading with no way to tell whose sentence was whose.
    it "keeps the Ministry's Polish and this project's English in separate columns" do
      # The **whole** tail of the row, not just the last two cells: matching `"| — | why |"`
      # alone still passed when the English was duplicated into the Polish column as well.
      described_class::UNMAPPED.each_value do |entry|
        expect(rendered).to include("| — | — | #{entry[:why]} |"), entry[:why][0, 40]
      end
    end

    it "labels the Polish column as quoted rather than translated" do
      expect(rendered).to include("The Ministry's description (Polish, verbatim)")
    end

    # The negative list is the answer to "is my field supported", so it has to name the
    # elements a reader will actually look for — and must not name the containers this model
    # walks through, which it did while counting only the last segment of each declared path.
    it "names what the model does not carry, and only that" do
      absent = rendered.lines.grep(%r{^\| `Faktura/Fa` \|}).first

      expect(absent).to include("`P_6`", "`Rozliczenie`", "`P_14_1W`", "`Platnosc`")
      expect(rendered.lines.grep(/^\| `Faktura` \|/).first).not_to include("`Fa`", "`Naglowek`")
    end

    it "orders an element carried by two models deterministically" do
      expect(rendered).to include("| `NIP` | `Buyer#nip`, `Seller#nip` |")
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

    # A missing file is stale by definition, and answering that beats raising ENOENT out of a
    # predicate — which is what the first version did.
    it "is true when the document is absent altogether" do
      allow(File).to receive(:exist?).with(described_class::OUT).and_return(false)

      expect(described_class).to be_stale
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
