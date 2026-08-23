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
end
