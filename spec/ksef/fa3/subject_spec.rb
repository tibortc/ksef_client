# frozen_string_literal: true

RSpec.describe Ksef::FA3::Subject do
  def address = Ksef::FA3::Address.new(line1: "Prosta 1, 00-001 Warszawa")

  def subject_with(**overrides)
    described_class.new(nip: "9999999999", name: "ACME sp. z o.o.", address: address, **overrides)
  end

  describe "the two roles are not symmetric" do
    # docs/REFERENCE.md §8.2: the buyer carries two mandatory flags the seller has no
    # elements for. Omitting them makes the document schema-invalid.
    it "gives a buyer JST and GV, and a seller neither" do
      expect(subject_with.to_fa3(role: :buyer).keys).to include("JST", "GV")
      expect(subject_with.to_fa3(role: :seller).keys).not_to include("JST", "GV")
    end

    it "defaults both flags to no" do
      content = subject_with.to_fa3(role: :buyer)

      expect(content["JST"]).to eq("2")
      expect(content["GV"]).to eq("2")
    end

    it "writes them as 1 when set" do
      content = subject_with(local_government_unit: true, vat_group_member: true).to_fa3(role: :buyer)

      expect(content["JST"]).to eq("1")
      expect(content["GV"]).to eq("1")
    end
  end

  # `TPodmiot1` is a plain sequence of NIP and Nazwa; `TPodmiot2` wraps Nazwa in an
  # `<xsd:sequence minOccurs="0">` after a four-way identification choice
  # (docs/REFERENCE.md §8.2a). So the name is optional for exactly one of the two.
  describe "the name, which only the buyer may omit" do
    it "omits Nazwa entirely for a nameless buyer" do
      identity = subject_with(name: nil).to_fa3(role: :buyer)["DaneIdentyfikacyjne"]

      expect(identity).to eq("NIP" => "9999999999")
    end

    # Written empty it would fail TZnakowy512's minimum length, turning a legal buyer into
    # an invalid document.
    it "does not write an empty element" do
      expect(subject_with(name: nil).to_fa3(role: :buyer)["DaneIdentyfikacyjne"]).not_to have_key("Nazwa")
    end

    it "refuses a nameless seller, whose type makes it mandatory" do
      expect { subject_with(name: nil).to_fa3(role: :seller) }
        .to raise_error(Ksef::ValidationError, /seller \(Podmiot1\) must have a name/)
    end
  end

  describe "the NIP" do
    it "is validated on the way out, with the role named" do
      expect { subject_with(nip: "9999999998").to_fa3(role: :seller) }
        .to raise_error(Ksef::ValidationError, /seller NIP .* invalid check digit/)
    end

    it "is normalised from the forms an ERP actually sends" do
      expect(subject_with(nip: "PL999-999-99-99").to_fa3(role: :seller)["DaneIdentyfikacyjne"]["NIP"])
        .to eq("9999999999")
    end
  end

  # `Podmiot1/Adres` is mandatory; `Podmiot2/Adres` is minOccurs="0" — "opcjonalne dla
  # przypadków określonych w art. 106e ust. 5 pkt 3", the simplified invoice (§8.2a).
  describe "the address, which only the buyer may omit" do
    it "omits Adres entirely for an address-less buyer" do
      content = described_class.new(nip: "1111111111", name: "Klient").to_fa3(role: :buyer)

      expect(content).not_to have_key("Adres")
      expect(content.keys).to eq(%w[DaneIdentyfikacyjne JST GV])
    end

    it "refuses an address-less seller" do
      expect { described_class.new(nip: "9999999999", name: "ACME").to_fa3(role: :seller) }
        .to raise_error(Ksef::ValidationError, /seller \(Podmiot1\) must have an address/)
    end
  end

  describe "#with" do
    it "re-runs the constructor, so the NIP is still normalised on serialisation" do
      changed = subject_with.with(nip: "PL111-111-11-11")

      expect(changed.to_fa3(role: :buyer)["DaneIdentyfikacyjne"]["NIP"]).to eq("1111111111")
    end
  end
end
