# frozen_string_literal: true

RSpec.describe Ksef::FA3::Issue do
  def issue(field, message) = described_class.new(field: field, message: message)

  it "renders as field then message, so a list of them prints readably" do
    expect(issue("lines[2].vat_rate", "is required").to_s).to eq("lines[2].vat_rate: is required")
  end

  it "sorts by its rendering, keeping error lists stable and diffable" do
    unsorted = [issue("number", "b"), issue("currency", "a"), issue("annotations", "c")]

    expect(unsorted.sort.map(&:field)).to eq(%w[annotations currency number])
  end

  # `include Comparable` would place `Comparable#==` ahead of `Data#==`, and that `==` delegates
  # to `<=>` on the rendering — so issues whose renderings coincide compared equal despite
  # different fields, an Issue compared equal to a bare String, and `==` disagreed with `hash`.
  describe "equality, which is Data's and not Comparable's" do
    it "distinguishes issues whose renderings coincide" do
      expect(issue("a", "b: c")).not_to eq(issue("a: b", "c"))
    end

    it "is not equal to a String that renders the same" do
      expect(issue("a", "b")).not_to eq("a: b")
    end

    it "keeps == and hash agreeing, so Hash and Array membership match" do
      one = issue("number", "is required")
      same = issue("number", "is required")

      expect(one).to eq(same)
      expect(one.hash).to eq(same.hash)
      expect({ one => :x }[same]).to eq(:x)
      expect([one].include?(same)).to be(true)
    end

    it "does not include Comparable" do
      expect(described_class.ancestors).not_to include(Comparable)
    end
  end
end
