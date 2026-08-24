# frozen_string_literal: true

RSpec.describe Ksef::UPO::Validator do
  # All six of upstream's worked examples, pinned at the same commit as the schema they fail.
  # They are the regression fixtures for §14.3: a correct implementation accepts every one.
  let(:examples) { Dir[File.expand_path("../../fixtures/upo/*.xml", __dir__)].sort }

  def read(path) = File.read(path, encoding: "UTF-8")

  it "compiles the pinned schema offline, with no rewriting" do
    expect(described_class.schema).to be_a(Nokogiri::XML::Schema)
  end

  # The heart of §14.3. Every example fails upstream's own schema on exactly one element, so
  # a strict validator would reject every UPO that TEST issues.
  describe "upstream's six worked examples" do
    it "finds all six of them" do
      expect(examples.size).to eq(6)
    end

    it "accepts every one" do
      results = examples.map { |path| described_class.validate(read(path)) }

      expect(results).to all(be_valid)
    end

    it "reports each one's single discrepancy as a warning, not an error" do
      results = examples.map { |path| described_class.validate(read(path)) }

      expect(results.map { |r| r.errors.size }).to all(eq(0))
      expect(results.map { |r| r.warnings.size }).to all(eq(1))
      expect(results).to all(be_environment_marked)
    end

    it "names the element and the observed value in the warning" do
      warning = described_class.validate(read(examples.first)).warnings.first

      expect(warning).to include("NazwaPodmiotuPrzyjmujacego")
      expect(warning).to include("środowisko testowe (TE)")
    end

    it "reads the receiving party from the document, so the environment is identifiable" do
      parties = examples.map { |path| described_class.validate(read(path)).receiving_party }

      expect(parties.uniq).to eq(["Ministerstwo Finansów - środowisko testowe (TE)"])
    end

    # None of them is clean, which is the point: valid? and clean? are different questions.
    it "reports none of them as clean" do
      results = examples.map { |path| described_class.validate(read(path)) }

      expect(results.map(&:clean?)).to all(be(false))
    end
  end

  describe "a UPO carrying the fixed value, as production is expected to" do
    subject(:result) { described_class.validate(production) }

    let(:production) do
      read(examples.first).sub(
        "Ministerstwo Finansów - środowisko testowe (TE)", "Ministerstwo Finansów"
      )
    end

    it "is clean, with no warning at all" do
      expect(result).to be_clean
      expect(result.warnings).to be_empty
      expect(result.errors).to be_empty
    end

    it "is not flagged as environment-marked" do
      expect(result).not_to be_environment_marked
    end

    it "reports the bare receiving-party name" do
      expect(result.receiving_party).to eq("Ministerstwo Finansów")
    end
  end

  describe "genuine schema violations" do
    # The warning is scoped to one element's fixed-value constraint. Anything else the
    # schema objects to must still be an error, or relaxing one known defect would quietly
    # relax everything.
    it "reports a structural problem as an error" do
      broken = read(examples.first).sub("</Potwierdzenie>", "<Nonsense/></Potwierdzenie>")
      result = described_class.validate(broken)

      expect(result.errors).not_to be_empty
      expect(result).not_to be_valid
    end

    it "keeps the expected warning alongside a real error" do
      broken = read(examples.first).sub("</Potwierdzenie>", "<Nonsense/></Potwierdzenie>")
      result = described_class.validate(broken)

      expect(result.warnings.size).to eq(1)
      expect(result.messages.size).to eq(result.errors.size + 1)
    end

    it "treats a document that is not a UPO at all as invalid" do
      expect(described_class.validate("<Something/>")).not_to be_valid
    end

    it "has no receiving party to report for a non-UPO" do
      expect(described_class.validate("<Something/>").receiving_party).to be_nil
    end
  end

  # §14.3: validation is a diagnostic, never a gate on storing legal proof of receipt.
  # Offering a raising method would make gating the path of least resistance.
  it "offers no validate! that would invite gating on the result" do
    expect(described_class).not_to respond_to(:validate!)
  end

  describe ".valid?" do
    it "is true for a UPO whose only discrepancy is the environment marker" do
      expect(described_class).to be_valid(read(examples.first))
    end

    it "is false for a genuine violation" do
      expect(described_class.valid?("<Something/>")).to be(false)
    end
  end

  describe "the inputs it accepts" do
    it "takes a String, a parsed document, or a UPO::Document" do
      xml = read(examples.first)
      wrapped = Ksef::UPO::Document.new(xml: xml, published_hash: nil, source: :api)

      expect(described_class.validate(xml)).to be_valid
      expect(described_class.validate(Nokogiri::XML(xml))).to be_valid
      expect(described_class.validate(wrapped)).to be_valid
    end

    it "is reachable straight from a Document" do
      wrapped = Ksef::UPO::Document.new(xml: read(examples.first), published_hash: nil, source: :api)

      expect(wrapped.validate).to be_environment_marked
    end
  end

  describe Ksef::UPO::Validation do
    it "summarises itself for a log line" do
      clean = described_class.new(errors: [], warnings: [], receiving_party: "MF")
      messy = described_class.new(errors: %w[a b], warnings: %w[c], receiving_party: nil)

      expect(clean.to_s).to eq("valid")
      expect(messy.to_s).to eq("2 error(s), 1 warning(s)")
    end
  end

  # A real UPO is XAdES-signed by the Ministry (§12) — that is what makes it proof of receipt.
  # `upo-v4-3.xsd` declares no `ds:Signature` anywhere, and **not one of upstream's six
  # examples is signed**, so offline nothing revealed that a genuine UPO fails upstream's own
  # schema on the signature element. The first live nightly did, 2026-08-24 (§14.7).
  describe "a signed UPO, as KSeF actually issues them" do
    # The Ministry's enveloped signature, reduced to the part that matters here: an element in
    # the xmldsig namespace that the UPO schema does not declare.
    def signed(path)
      xml = read(path)
      signature = <<~SIG
        <ds:Signature xmlns:ds="#{described_class::SIGNATURE_NAMESPACE}">
          <ds:SignedInfo><ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/></ds:SignedInfo>
          <ds:SignatureValue>Zm9v</ds:SignatureValue>
        </ds:Signature>
      SIG
      root = Nokogiri::XML(xml).root.name
      xml.sub("</#{root}>", "#{signature}</#{root}>")
    end

    it "would fail the pinned schema outright, which is the defect" do
      document = Nokogiri::XML(signed(examples.first))
      raw = described_class.schema.validate(document).map(&:message)

      expect(raw.any? { |m| m.include?("Signature") && m.include?("not expected") }).to be(true)
    end

    it "validates once the signature is set aside" do
      result = described_class.validate(signed(examples.first))

      expect(result.errors).to be_empty
      expect(result).to be_valid
    end

    it "keeps reporting the environment-marker warning of §14.3" do
      result = described_class.validate(signed(examples.first))

      expect(result.warnings.size).to eq(1)
      expect(result.receiving_party).to include("Ministerstwo Finans")
    end

    # Stripping is not leniency: anything else wrong with the document still surfaces.
    it "still reports a genuine violation alongside a signature" do
      broken = signed(examples.first).sub("<NumerReferencyjny", "<Nieoczekiwany/><NumerReferencyjny")

      expect(described_class.validate(broken).errors).not_to be_empty
    end

    it "does not mutate the document it was given" do
      xml = signed(examples.first)
      document = Nokogiri::XML(xml)
      described_class.validate(document)

      expect(document.xpath("//ds:Signature", "ds" => described_class::SIGNATURE_NAMESPACE))
        .not_to be_empty
    end

    describe ".signed?" do
      it "is true for a signed document and false for upstream's examples" do
        expect(described_class.signed?(signed(examples.first))).to be(true)
        examples.each { |path| expect(described_class.signed?(read(path))).to be(false) }
      end
    end
  end
end
