# frozen_string_literal: true

require_relative "../../support/fa3_corpus"

RSpec.describe Ksef::FA3::ModelValidator do
  def address(**overrides) = Ksef::FA3::Address.new(line1: "Prosta 1", **overrides)

  def subject_for(**overrides)
    Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME", address: address, **overrides)
  end

  def line(**overrides)
    Ksef::FA3::Line.new(name: "X", quantity: 1, unit: "szt.",
                        net_unit_price: 100, vat_rate: "23", **overrides)
  end

  def invoice(**overrides)
    Ksef::FA3::Invoice.new(seller: subject_for, buyer: subject_for(nip: "1111111111", name: "Klient"),
                           number: "FV/1", issue_date: Date.today, lines: [line], **overrides)
  end

  def fields_for(**overrides) = described_class.errors_for(invoice(**overrides)).map(&:field)

  it "finds nothing wrong with a sound invoice" do
    expect(described_class.errors_for(invoice)).to be_empty
  end

  # DESIGN.md §7.7 asks for field-addressed errors, and collecting rather than raising is what
  # lets a caller fix everything in one pass.
  it "reports every problem at once, each addressed to its field" do
    broken = invoice(
      number: "", currency: "XYZ", invoice_type: "NOPE",
      seller: subject_for(nip: "9999999998"), lines: [line(vat_rate: "24")]
    )

    expect(broken.errors.map(&:field))
      .to contain_exactly("number", "currency", "invoice_type", "seller.nip", "lines[0].vat_rate")
  end

  describe "NIP checksums" do
    # Stricter than TEST on purpose: KSeF validates these in production only (§15.3), so no
    # integration run can cover the rule and relaxing it moves the failure to production.
    it "rejects a check digit that does not add up" do
      issue = described_class.errors_for(invoice(seller: subject_for(nip: "9999999998"))).first

      expect(issue.field).to eq("seller.nip")
      expect(issue.message).to include("invalid check digit: expected 9, got 8")
    end

    it "accepts the written forms an ERP sends" do
      expect(described_class.errors_for(invoice(seller: subject_for(nip: "PL999-999-99-99")))).to be_empty
    end

    it "checks the buyer as well as the seller" do
      expect(fields_for(buyer: subject_for(nip: "1111111112", name: "K"))).to include("buyer.nip")
    end
  end

  describe "enum membership, read from the generated metadata" do
    it "checks the currency, the invoice type, the country and each rate code" do
      expect(fields_for(currency: "XYZ")).to include("currency")
      expect(fields_for(invoice_type: "NOPE")).to include("invoice_type")
      expect(fields_for(seller: subject_for(address: address(country: "ZZ")))).to include("seller.address.country")
      expect(fields_for(lines: [line(vat_rate: "24")])).to include("lines[0].vat_rate")
    end

    it "accepts the non-numeric rate codes, which are half of TStawkaPodatku" do
      ["zw", "oo", "np I", "0 WDT"].each do |code|
        expect(described_class.errors_for(invoice(lines: [line(vat_rate: code)]))).to be_empty, code
      end
    end
  end

  describe "the two fields only a buyer may omit (§8.2a)" do
    it "requires a seller's name and address" do
      expect(fields_for(seller: subject_for(name: nil))).to include("seller.name")
      expect(fields_for(seller: Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME")))
        .to include("seller.address")
    end

    it "allows a buyer to omit both" do
      nameless = Ksef::FA3::Subject.new(nip: "1111111111")

      expect(described_class.errors_for(invoice(buyer: nameless))).to be_empty
    end
  end

  describe "string lengths, from the schema's own facets" do
    it "rejects a name beyond TZnakowy512" do
      issue = described_class.errors_for(invoice(seller: subject_for(name: "ż" * 513))).first

      expect(issue.field).to eq("seller.name")
      expect(issue.message).to eq("is 513 characters; the schema allows 512")
    end

    it "rejects an invoice number beyond TZnakowy's 256" do
      expect(fields_for(number: "F" * 257)).to include("number")
    end

    it "accepts a name at exactly the limit" do
      expect(described_class.errors_for(invoice(seller: subject_for(name: "a" * 512)))).to be_empty
    end

    # minLength is 1, so present-but-blank is a violation rather than an absent value.
    it "rejects blank text where the schema demands at least one character" do
      expect(fields_for(number: "   ")).to include("number")
      expect(fields_for(seller: subject_for(name: ""))).to include("seller.name")
    end
  end

  # Nil where the schema demands a value. The constructor stops most of these, but a model
  # built by hand — or by a future parser for a type this one does not carry — can still
  # arrive with a hole in it, and "is required" is a better answer than a NoMethodError.
  describe "values that are absent rather than wrong" do
    it "reports a missing subject" do
      expect(described_class.errors_for(invoice(buyer: nil)))
        .to contain_exactly(an_object_having_attributes(field: "buyer", message: "is required"))
    end

    it "reports a missing invoice number" do
      expect(fields_for(number: nil)).to include("number")
    end

    it "reports a missing enum value rather than treating nil as valid" do
      expect(fields_for(currency: nil)).to include("currency")
      expect(fields_for(lines: [line(vat_rate: nil)])).to include("lines[0].vat_rate")
    end
  end

  # Both text types derive from xsd:token, whose whiteSpace facet is collapse, and XSD applies
  # that *before* maxLength. Measuring the raw string made tier 1 stricter than the schema —
  # and strictness on the send path means refusing documents KSeF admits.
  describe "whitespace, which the schema collapses before measuring" do
    it "agrees with the schema about a long name full of whitespace" do
      padded = "A#{" " * 300}B"

      expect(described_class.errors_for(invoice(number: padded))).to be_empty
      expect(Ksef::FA3::Validator.errors_for(invoice(number: padded).to_xml)).to be_empty
    end

    it "still rejects a name that is too long once collapsed" do
      expect(fields_for(seller: subject_for(name: (["ab"] * 300).join("  ")))).to include("seller.name")
    end

    it "accepts an enum value with stray whitespace, as the schema does" do
      expect(described_class.errors_for(invoice(currency: " PLN "))).to be_empty
    end

    # The real document that exposed this: thirteen line names of 577 raw characters collapsing
    # to 500, XSD-clean and rejected by tier 1 until 2026-08-24.
    it "passes the pinned upstream sample that used to be falsely rejected" do
      xml = FA3Corpus.read("ksef-pdf-generator/invoice.xml")

      expect(Ksef::FA3.parse(xml).errors).to be_empty
    end
  end

  # Text tagged UTF-8 but holding invalid bytes used to raise Encoding::CompatibilityError out
  # of `String#strip` — from a method whose entire purpose is answering "what is wrong here?",
  # on the input class §15.1 calls the likeliest real-world rejection.
  describe "text that is not valid UTF-8" do
    let(:mojibake) { "Kowalsk\xFF".dup.force_encoding("UTF-8") }

    it "is reported rather than raised" do
      issue = described_class.errors_for(invoice(seller: subject_for(name: mojibake))).first

      expect(issue.field).to eq("seller.name")
      expect(issue.message).to include("not valid UTF-8")
    end

    it "does not raise from #errors either" do
      expect { invoice(number: mojibake).errors }.not_to raise_error
    end

    it "does not let an invalid-encoding value slip past the enum check" do
      expect(fields_for(currency: mojibake)).to include("currency")
    end
  end

  # Characters outside XML's Char production are not the *discouraged* set of §15.1 — they
  # cannot appear in any XML document, and libxml2 answers with a bare ArgumentError.
  describe "characters XML does not permit at all" do
    it "reports a NUL byte against its field" do
      issue = described_class.errors_for(invoice(number: "FV/\u0000/1")).first

      expect(issue.field).to eq("number")
      expect(issue.message).to include("U+0000")
    end
  end

  # The contract's known holes, closed 2026-08-24: both were fields the model tier never
  # inspected, so they passed here and made the serializer raise.
  describe "fields that used to slip past into a serialisation failure" do
    it "checks the shape of the annotations block" do
      issues = described_class.errors_for(invoice(annotations: { "Nieoczekiwany" => "1" }))

      expect(issues.map(&:field)).to eq(["annotations"])
      expect(issues.first.message).to include("not an element of Adnotacje")
    end

    it "accepts the defaults and a legitimate override" do
      declared = Ksef::FA3::Invoice::DEFAULT_ANNOTATIONS.merge("P_16" => "1")

      expect(described_class.errors_for(invoice(annotations: declared))).to be_empty
    end

    # Defence against a codegen change that re-keys the anonymous Adnotacje type: that is a
    # generator problem, not a caller's, and no reason to reject their annotations.
    it "checks nothing when the generated metadata no longer knows the type" do
      allow(Ksef::FA3::Generated::Types)
        .to receive(:ordered_elements).with(described_class::ANNOTATIONS_TYPE).and_return([])

      expect(described_class.errors_for(invoice(annotations: { "Nieoczekiwany" => "1" }))).to be_empty
    end

    it "rejects annotations that are not a Hash" do
      expect(fields_for(annotations: "none")).to include("annotations")
    end

    # JST and GV go through Formatting.flag, which raises on anything not boolean-ish.
    it "checks the buyer's two yes/no flags" do
      odd = subject_for(nip: "1111111111", name: "K", vat_group_member: "yes")

      expect(fields_for(buyer: odd)).to include("buyer.vat_group_member")
    end

    it "does not look for those flags on a seller, which has no such elements" do
      odd = subject_for(vat_group_member: "yes")

      expect(described_class.errors_for(invoice(seller: odd))).to be_empty
    end
  end

  # A mistyped member used to surface as NoMethodError from inside the validator.
  describe "members of the wrong type" do
    it "reports a subject that is not a Subject" do
      expect(fields_for(buyer: "Klient S.A.")).to include("buyer")
    end

    it "reports an address that is not an Address" do
      expect(fields_for(seller: subject_for(address: "Prosta 1"))).to include("seller.address")
    end

    it "reports a line that is not a Line" do
      expect(fields_for(lines: [line, "second"])).to include("lines[1]")
    end
  end

  describe "the issue date (§15.4)" do
    it "accepts today and the recent past" do
      expect(described_class.errors_for(invoice(issue_date: Date.today))).to be_empty
      expect(described_class.errors_for(invoice(issue_date: Date.today - 60))).to be_empty
    end

    # The comparison KSeF makes is against *its* acceptance date, in its own timezone. A strict
    # local comparison would reject good invoices around midnight for a caller west of Warsaw,
    # so one day of slack is deliberate and the same-day boundary is left to the service.
    it "tolerates tomorrow, because the timezone is not ours to assume" do
      expect(described_class.errors_for(invoice(issue_date: Date.today + 1))).to be_empty
    end

    # A DateTime is a Date, and comparing one against `Date.today + 1` made the tolerance
    # depend on the clock. Invoice now converts it, so both give the same verdict.
    it "treats a DateTime the same as the Date it falls on" do
      expect(described_class.errors_for(invoice(issue_date: DateTime.now + 1))).to be_empty
      expect(invoice(issue_date: DateTime.now).issue_date).to be_an_instance_of(Date)
    end

    it "rejects a date that is unambiguously in the future" do
      issue = described_class.errors_for(invoice(issue_date: Date.today + 2)).first

      expect(issue.field).to eq("issue_date")
      expect(issue.message).to include("is in the future")
    end
  end

  # The contract that makes tier 1 worth running first: what it passes, the serializer accepts.
  describe "its contract with the serializer" do
    it "catches a line whose net can be neither read nor derived" do
      lump = line(quantity: nil, net_unit_price: nil, net_amount: nil)

      expect(fields_for(lines: [lump])).to include("lines[0]")
    end

    it "means to_xml does not raise for anything it accepts" do
      [invoice, invoice(lines: [line(vat_rate: "zw")]),
       invoice(buyer: Ksef::FA3::Subject.new(nip: "1111111111"))].each do |candidate|
        expect(described_class.errors_for(candidate)).to be_empty
        expect { candidate.to_xml }.not_to raise_error
      end
    end
  end
end
