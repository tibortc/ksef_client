# frozen_string_literal: true

# Asserts the *generated* metadata against facts independently recorded in
# docs/REFERENCE.md §8 and DESIGN.md. If the generator regresses, or upstream changes the
# schema, these fail rather than silently feeding wrong ordering into the serializer.
RSpec.describe Ksef::FA3::Generated do
  describe Ksef::FA3::Generated::Enums do
    it "captures every named enumerated simpleType across the pinned schemas" do
      expect(described_class::ALL.size).to eq(21)
    end

    # DESIGN.md §7.4: seven invoice types, in this order.
    it "lists exactly the seven invoice types" do
      expect(described_class.values_for("TRodzajFaktury"))
        .to eq(%w[VAT KOR ZAL ROZ UPR KOR_ZAL KOR_ROZ])
    end

    # Values keep schema order, and several are not bare numbers — a naive numeric
    # coercion anywhere in the VAT path would corrupt these.
    it "keeps VAT rate codes verbatim, including the non-numeric ones" do
      expect(described_class.values_for("TStawkaPodatku"))
        .to eq(["23", "22", "8", "7", "5", "4", "3", "0 KR", "0 WDT", "0 EX", "zw", "oo", "np I", "np II"])
    end

    it "pulls country codes from the base schema, not just the EU subset" do
      expect(described_class.values_for("TKodKraju").size).to eq(254)
      expect(described_class.values_for("TKodyKrajowUE").size).to eq(28)
    end

    it "pulls currency codes" do
      expect(described_class.values_for("TKodWaluty")).to include("PLN", "EUR", "USD")
    end

    describe ".valid?" do
      it "accepts a permitted value" do
        expect(described_class.valid?("TStawkaPodatku", "23")).to be(true)
      end

      it "rejects an impermissible value" do
        expect(described_class.valid?("TStawkaPodatku", "99")).to be(false)
      end

      it "rejects everything for an unknown type rather than raising" do
        expect(described_class.valid?("TNotAThing", "23")).to be(false)
      end
    end

    it "returns nil for an unknown type" do
      expect(described_class.values_for("TNotAThing")).to be_nil
    end
  end

  describe Ksef::FA3::Generated::Types do
    it "covers the named types plus every anonymous one reachable from the root" do
      expect(described_class::ALL.size).to eq(59)
    end

    # This ordering is the whole point of the codegen: KSeF rejects documents whose
    # elements appear out of sequence.
    it "preserves the root element order" do
      expect(described_class.ordered_elements("Faktura").map { |e| e[:name] })
        .to eq(%w[Naglowek Podmiot1 Podmiot2 Podmiot3 PodmiotUpowazniony Fa Stopka Zalacznik])
    end

    it "records occurrence rules, with unbounded as nil" do
      podmiot3 = described_class.ordered_elements("Faktura").find { |e| e[:name] == "Podmiot3" }
      expect(podmiot3).to include(min: 0, max: 100)

      naglowek = described_class.ordered_elements("Faktura").find { |e| e[:name] == "Naglowek" }
      expect(naglowek).to include(min: 1, max: 1, type: "tns:TNaglowek")
    end

    it "captures the fixed header attributes from REFERENCE.md §8" do
      attrs = described_class::ALL.fetch("TNaglowek")[:attributes]
      expect(attrs).to contain_exactly(
        { name: "kodSystemowy", type: "xsd:string", use: "required", fixed: "FA (3)" },
        { name: "wersjaSchemy", type: "xsd:string", use: "required", fixed: "1-0E" }
      )
    end

    it "keys anonymous types by path, since leaf names collide" do
      expect(described_class::ALL.keys.grep(/DaneKontaktowe/)).to contain_exactly(
        "Faktura/Podmiot1/DaneKontaktowe",
        "Faktura/Podmiot2/DaneKontaktowe",
        "Faktura/Podmiot3/DaneKontaktowe",
        "Faktura/PodmiotUpowazniony/DaneKontaktowe"
      )
    end

    describe "choice fidelity" do
      # Regression guard. An earlier generator unwrapped the root compositor, which turned
      # these four types' "exactly one of" into "all of these, in order" — a validator
      # built on that would have accepted mutually exclusive branches together.
      it "flags the four types whose root compositor is a choice" do
        flagged = described_class::ALL.keys.select { |k| described_class.root_choice?(k) }
        expect(flagged).to contain_exactly(
          "Faktura/Fa/Adnotacje/Zwolnienie",
          "Faktura/Fa/Adnotacje/NoweSrodkiTransportu",
          "Faktura/Fa/Adnotacje/PMarzy",
          "Faktura/Fa/FakturaZaliczkowa"
        )
      end

      it "does not mistake a sequence root for a choice" do
        expect(described_class.root_choice?("Faktura")).to be(false)
        expect(described_class.root_choice?("TNaglowek")).to be(false)
      end

      # Three levels deep: a choice of sequences, one of which contains a further
      # optional choice. Flattening any of it would lose information the validator needs.
      it "preserves nested choice branches, including a choice inside a branch" do
        key = described_class::ALL.keys.grep(/NowySrodekTransportu$/).first
        choice = described_class::ALL.fetch(key)[:content][:particles].find { |p| p[:kind] == :choice }

        expect(choice[:particles].map { |b| b[:kind] }).to eq(%i[sequence sequence sequence])

        first, second, third = choice[:particles]
        expect(first[:particles].map { |p| p[:name] || p[:kind] }).to eq(["P_22B", :choice, "P_22BT"])
        expect(second[:particles].map { |p| p[:name] }).to eq(%w[P_22C P_22C1])
        expect(third[:particles].map { |p| p[:name] }).to eq(%w[P_22D P_22D1])
      end

      it "records the optional inner choice's own occurrence rules" do
        key = described_class::ALL.keys.grep(/NowySrodekTransportu$/).first
        choice = described_class::ALL.fetch(key)[:content][:particles].find { |p| p[:kind] == :choice }
        inner = choice[:particles].first[:particles].find { |p| p[:kind] == :choice }

        expect(inner).to include(kind: :choice, min: 0, max: 1)
        expect(inner[:particles].map { |p| p[:name] }).to eq(%w[P_22B1 P_22B2 P_22B3 P_22B4])
      end
    end

    it "exposes content as a single root particle, not a bare list" do
      expect(described_class::ALL.fetch("Faktura")[:content]).to include(kind: :sequence)
    end

    it "returns an empty ordering for an unknown key rather than raising" do
      expect(described_class.ordered_elements("Nope")).to eq([])
    end
  end

  describe "the generated files themselves" do
    let(:files) { Dir[File.expand_path("../../../lib/ksef/fa3/generated/*.rb", __dir__)] }

    it "exist" do
      expect(files.map { |f| File.basename(f) }).to contain_exactly("enums.rb", "types.rb")
    end

    it "each carry the do-not-edit header tying them to the schema digest" do
      files.each do |f|
        head = File.read(f, encoding: "UTF-8")[0, 600]
        expect(head).to include("GENERATED by `rake fa3:generate` from FA(3) 1-0E — DO NOT EDIT")
        expect(head).to match(/SHA256: [0-9a-f]{64}/)
      end
    end
  end
end
