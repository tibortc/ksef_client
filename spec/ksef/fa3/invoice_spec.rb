# frozen_string_literal: true

RSpec.describe Ksef::FA3::Invoice do
  def seller
    Ksef::FA3::Subject.new(
      nip: "9999999999", name: "ACME sp. z o.o.",
      address: Ksef::FA3::Address.new(street: "Prosta 1", city: "Warszawa", postal_code: "00-001")
    )
  end

  def buyer
    Ksef::FA3::Subject.new(
      nip: "1111111111", name: "Klient S.A.",
      address: Ksef::FA3::Address.new(street: "Długa 2", city: "Kraków", postal_code: "30-001")
    )
  end

  def line(rate: "23", quantity: 10, price: "150", **rest)
    Ksef::FA3::Line.new(name: "Consulting", quantity: quantity, unit: "godz.",
                        net_unit_price: BigDecimal(price), vat_rate: rate, **rest)
  end

  def invoice(**overrides)
    described_class.new(
      seller: seller, buyer: buyer, number: "FV/2026/08/001",
      issue_date: Date.new(2026, 8, 22), issued_at: Time.utc(2026, 8, 22, 10, 0, 0),
      lines: [line], **overrides
    )
  end

  describe "the golden file" do
    let(:golden) do
      File.read(File.expand_path("../../fixtures/fa3/golden/vat_single_line.xml", __dir__), encoding: "UTF-8")
    end

    # If this fails, either the serializer changed or the schema did. Regenerate
    # deliberately and read the diff — do not update the fixture to make it pass.
    it "reproduces the approved output byte for byte" do
      expect(invoice.to_xml).to eq(golden)
    end

    it "is XSD-valid" do
      expect(Ksef::FA3::Validator.errors_for(golden)).to be_empty
    end
  end

  describe "totals" do
    it "computes net, VAT and gross from the lines" do
      expect(invoice).to have_attributes(
        net_total: BigDecimal("1500"),
        vat_total: BigDecimal("345"),
        gross_total: BigDecimal("1845")
      )
    end

    it "sums across several rates into their own buckets" do
      multi = invoice(lines: [line(rate: "23", price: "100", quantity: 1),
                              line(rate: "8", price: "200", quantity: 1),
                              line(rate: "zw", price: "50", quantity: 1)])

      expect(multi.net_by_rate).to eq("23" => BigDecimal("100"), "8" => BigDecimal("200"),
                                      "zw" => BigDecimal("50"))
      expect(multi.vat_total).to eq(BigDecimal("39")) # 23 + 16 + 0
    end

    it "charges no VAT on a non-numeric rate code" do
      expect(invoice(lines: [line(rate: "zw")]).vat_total).to eq(0)
    end

    it "honours an overridden line net, for ERP-as-source-of-truth callers" do
      overridden = invoice(lines: [line(net_amount: BigDecimal("1234.56"))])
      expect(overridden.net_total).to eq(BigDecimal("1234.56"))
    end

    it "exposes a per-line gross for callers displaying line totals" do
      expect(line.gross).to eq(BigDecimal("1845"))
      expect(line(rate: "zw").gross).to eq(BigDecimal("1500"))
    end
  end

  # A zero-rated or exempt bucket has no P_14_* element at all — the schema provides
  # nowhere to put a tax amount (docs/REFERENCE.md §8.1a), so the serializer must not
  # invent one.
  describe "buckets without a tax element" do
    let(:doc) { Nokogiri::XML(invoice(lines: [line(rate: "zw")]).to_xml).remove_namespaces! }

    it "emits the net bucket" do
      expect(doc.at_xpath("//Fa/P_13_7")&.text).to eq("1500.00")
    end

    it "emits no paired tax element" do
      expect(doc.at_xpath("//Fa/P_14_7")).to be_nil
    end

    it "still validates" do
      expect(Ksef::FA3::Validator.valid?(invoice(lines: [line(rate: "zw")]).to_xml)).to be(true)
    end

    it "gives each zero rate its own distinct bucket" do
      mixed = invoice(lines: [line(rate: "0 WDT", price: "10", quantity: 1),
                              line(rate: "0 EX", price: "20", quantity: 1)])
      rendered = Nokogiri::XML(mixed.to_xml).remove_namespaces!

      expect(rendered.at_xpath("//Fa/P_13_6_2")&.text).to eq("10.00")
      expect(rendered.at_xpath("//Fa/P_13_6_3")&.text).to eq("20.00")
    end
  end

  # Both strategies are legal under Polish VAT law, and the difference is a real grosz
  # (DESIGN.md §7.3) — which is why the choice is explicit rather than silent.
  describe "rounding strategies" do
    # Three lines whose per-line VAT each round up, but whose summed net rounds down.
    let(:lines) { Array.new(3) { line(quantity: 1, price: "0.07", rate: "23") } }

    it "rounds per line by default" do
      # 0.07 * 23% = 0.0161 -> 0.02 each, three times = 0.06
      expect(invoice(lines: lines).vat_total).to eq(BigDecimal("0.06"))
    end

    it "rounds once per summary when asked" do
      # 0.21 * 23% = 0.0483 -> 0.05
      expect(invoice(lines: lines, rounding: :per_summary).vat_total).to eq(BigDecimal("0.05"))
    end

    it "rejects an unknown strategy rather than silently picking one" do
      expect { invoice(rounding: :bankers) }
        .to raise_error(Ksef::ValidationError, /Unknown rounding strategy/)
    end

    it "still produces a valid document under either strategy" do
      expect(Ksef::FA3::Validator.valid?(invoice(lines: lines, rounding: :per_summary).to_xml)).to be(true)
    end

    it "charges no VAT on an exempt line under summary rounding either" do
      exempt = invoice(lines: [line(rate: "zw")], rounding: :per_summary)
      expect(exempt.vat_by_rate).to eq("zw" => BigDecimal(0))
      expect(exempt.vat_total).to eq(0)
    end
  end

  describe "validation" do
    it "requires at least one line" do
      expect { invoice(lines: []) }.to raise_error(Ksef::ValidationError, /at least one line/)
      expect { invoice(lines: nil) }.to raise_error(Ksef::ValidationError, /at least one line/)
    end

    it "rejects a seller NIP that fails its checksum" do
      bad = Ksef::FA3::Subject.new(nip: "9999999998", name: "X",
                                   address: Ksef::FA3::Address.new(line1: "Prosta 1"))
      expect { invoice(seller: bad).to_xml }
        .to raise_error(Ksef::ValidationError, /seller NIP.*invalid check digit/)
    end

    it "exposes validate! and valid? against the schema" do
      expect(invoice.valid?).to be(true)
      expect(invoice.validate!).to be(true)
    end
  end

  # DESIGN.md §7.7's three tiers, as amended 2026-08-24: model checks, then document checks on
  # the serialized bytes, then the schema. Tier 3 does not exist — its catalogue is absent
  # upstream (docs/REFERENCE.md §15.6).
  describe "#errors across the tiers" do
    it "is empty for a sound invoice" do
      expect(invoice.errors).to be_empty
    end

    it "reports a model problem addressed to its field" do
      broken = invoice(number: "")

      expect(broken.errors.map(&:field)).to eq(["number"])
    end

    # The ordering is load-bearing, not cosmetic. Serialisation *raises* on a bad NIP, so
    # attempting it would replace a list of addressed errors with one exception about
    # whichever came first — and would hide the second problem entirely.
    it "stops at the model tier rather than trying to serialise an unserialisable invoice" do
      doomed = invoice(seller: Ksef::FA3::Subject.new(nip: "9999999998", name: "ACME",
                                                      address: Ksef::FA3::Address.new(line1: "P")),
                       number: "")

      expect { doomed.to_xml }.to raise_error(Ksef::ValidationError)
      expect(doomed.errors.map(&:field)).to contain_exactly("seller.nip", "number")
    end

    it "reports a document-tier problem the schema cannot see" do
      # U+0087, built by codepoint so it stays visible in a diff.
      offending = invoice(lines: [line.with(name: "Consulting#{0x87.chr(Encoding::UTF_8)}")])

      expect(Ksef::FA3::Validator.errors_for(offending.to_xml)).to be_empty
      expect(offending.errors.map(&:message)).to include(a_string_matching(/U\+0087/))
    end

    it "attributes a schema violation to the schema tier" do
      # Annotations the model will carry but the schema will not accept there.
      wrong = invoice(annotations: { "P_16" => "3" })

      expect(wrong.errors.map(&:field).uniq).to eq(["schema"])
    end

    # This used to be the counterexample to the model tier's contract: an unknown annotation
    # key passed the model and then made the serializer raise. The model tier now checks the
    # shape, so the issue is addressed to the field rather than landing as an unaddressed
    # `document:` complaint.
    it "addresses an unknown annotation to its field instead of letting serialisation refuse it" do
      unknown = invoice(annotations: { "Nieoczekiwany" => "1" })

      expect { unknown.to_xml }.to raise_error(Ksef::ValidationError)
      expect(unknown.errors.map(&:field)).to eq(["annotations"])
    end

    # The rescue behind that: whatever else serialisation might one day refuse, #errors answers
    # the question it was asked. Driven by stubbing, because the known holes are now closed and
    # a real counterexample is exactly what this guard exists to survive not having.
    it "reports an unanticipated serialisation refusal rather than raising it" do
      # A subclass rather than a stub: Invoice instances are frozen Data values.
      refusing = Class.new(described_class) do
        def to_xml = raise(Ksef::ValidationError, "something new")
      end

      expect(refusing.new(**invoice.to_h).errors.map(&:to_s)).to eq(["document: something new"])
    end

    it "does not swallow an error the model tier can describe properly" do
      expect(invoice(number: "").errors.map(&:field)).to eq(["number"])
    end

    it "is false from #valid? when something is wrong" do
      expect(invoice(number: "").valid?).to be(false)
      expect(invoice.valid?).to be(true)
    end

    # The ceiling is a per-context default an organisation can have raised (§15.5).
    it "forwards a negotiated size ceiling" do
      expect(invoice.errors(max_bytes: 10).map(&:message)).to include(a_string_matching(/accepts 10/))
      expect(invoice.valid?(max_bytes: 10)).to be(false)
      expect { invoice.validate!(max_bytes: 10) }.to raise_error(Ksef::ValidationError, /accepts 10/)
    end
  end

  describe "#validate!" do
    it "lists every problem, sorted, rather than only the first" do
      broken = invoice(number: "", currency: "XYZ")

      expect { broken.validate! }.to raise_error(Ksef::ValidationError) { |error|
        expect(error.message).to include("currency:", "number:")
        expect(error.message.index("currency:")).to be < error.message.index("number:")
      }
    end

    it "names the invoice, since a caller may be validating many" do
      expect { invoice(number: "").validate! }
        .to raise_error(Ksef::ValidationError, /Invoice "" is not valid/)
    end
  end

  # Several rate codes report into one bucket (§8.1a). Assigning per code instead of
  # accumulating let the last one win, understating the tax base while P_15 stayed correct —
  # an internally inconsistent invoice that the XSD accepts.
  describe "rate codes that share a summary bucket" do
    def rendered(*rates)
      lines = rates.map { |rate, price| line(rate: rate, price: price, quantity: 1) }
      Nokogiri::XML(invoice(lines: lines).to_xml).remove_namespaces!
    end

    it "sums 23% and 22% into P_13_1 and P_14_1" do
      doc = rendered(%w[23 100], %w[22 200])

      expect(doc.at_xpath("//Fa/P_13_1").text).to eq("300.00")
      expect(doc.at_xpath("//Fa/P_14_1").text).to eq("67.00")
      expect(doc.at_xpath("//Fa/P_15").text).to eq("367.00")
    end

    it "sums 8% and 7% into bucket two" do
      doc = rendered(%w[8 100], %w[7 100])

      expect(doc.at_xpath("//Fa/P_13_2").text).to eq("200.00")
      expect(doc.at_xpath("//Fa/P_14_2").text).to eq("15.00")
    end

    # The pair a review found mis-mapped: 3% belongs with 4% in the passenger-taxi bucket,
    # not in bucket five, which is OSS foreign VAT (§8.1a).
    it "sums 4% and 3% into P_13_4, leaving the OSS bucket untouched" do
      doc = rendered(%w[4 200], %w[3 100])

      expect(doc.at_xpath("//Fa/P_13_4").text).to eq("300.00")
      expect(doc.at_xpath("//Fa/P_14_4").text).to eq("11.00")
      expect(doc.at_xpath("//Fa/P_13_5")).to be_nil
      expect(doc.at_xpath("//Fa/P_14_5")).to be_nil
    end

    # Two non-taxable categories sharing a net bucket with no tax element at all.
    it "sums np I and np II into P_13_8" do
      doc = rendered(["np I", "100"], ["np II", "200"])

      expect(doc.at_xpath("//Fa/P_13_8").text).to eq("300.00")
      expect(doc.at_xpath("//Fa/P_14_8")).to be_nil
    end

    it "keeps the document internally consistent, which is the point" do
      doc = rendered(%w[23 100], %w[22 200])
      base = BigDecimal(doc.at_xpath("//Fa/P_13_1").text)
      tax = BigDecimal(doc.at_xpath("//Fa/P_14_1").text)

      expect(base + tax).to eq(BigDecimal(doc.at_xpath("//Fa/P_15").text))
      expect(Ksef::FA3::Validator.errors_for(invoice(lines: [line(rate: "23", price: "100", quantity: 1),
                                                             line(rate: "22", price: "200", quantity: 1)]).to_xml))
        .to be_empty
    end
  end

  describe "annotations" do
    it "defaults to not-applicable, so an ordinary invoice needs no knowledge of them" do
      expect(invoice.annotations).to eq(described_class::DEFAULT_ANNOTATIONS)
    end

    # The parser reads them; carrying them means re-serialising cannot deny a declaration the
    # document made. Two invoices differing only here are different invoices.
    it "is carried verbatim when given" do
      declared = described_class::DEFAULT_ANNOTATIONS.merge("P_16" => "1")
      doc = Nokogiri::XML(invoice(annotations: declared).to_xml).remove_namespaces!

      expect(doc.at_xpath("//Adnotacje/P_16").text).to eq("1")
      expect(invoice(annotations: declared)).not_to eq(invoice)
    end
  end

  # `Data#with` does not call a custom initialize on Ruby 3.2, which is the declared floor, so
  # every canonicalisation was bypassable through a public method there (see FA3::Canonical).
  describe "#with" do
    it "re-runs the constructor, so invariants still hold" do
      expect { invoice.with(rounding: :bankers) }
        .to raise_error(Ksef::ValidationError, /Unknown rounding strategy/)
      expect { invoice.with(lines: []) }.to raise_error(Ksef::ValidationError, /at least one line/)
    end

    it "canonicalises the replacement value too" do
      expect(invoice.with(issued_at: Time.utc(2026, 1, 2, 3, 4, 5)).issued_at)
        .to eq("2026-01-02T03:04:05Z")
    end

    it "keeps the retained document" do
      parsed = Ksef::FA3.parse(invoice.to_xml)

      expect(parsed.with(number: "FV/OTHER").raw_document).to be(parsed.raw_document)
    end
  end

  # These are mandatory in the schema but would be invisible to a caller writing an
  # ordinary domestic invoice (docs/REFERENCE.md §8.2).
  describe "defaults a caller should not have to know about" do
    let(:doc) { Nokogiri::XML(invoice.to_xml).remove_namespaces! }

    it "declares the buyer is not a local-government unit and not in a VAT group" do
      expect(doc.at_xpath("//Podmiot2/JST").text).to eq("2")
      expect(doc.at_xpath("//Podmiot2/GV").text).to eq("2")
    end

    it "emits all five mandatory annotation flags" do
      %w[P_16 P_17 P_18 P_18A P_23].each do |flag|
        expect(doc.at_xpath("//Adnotacje/#{flag}")&.text).to eq("2"), "expected #{flag} to be present"
      end
    end

    it "emits one branch of each mandatory root-choice wrapper" do
      expect(doc.at_xpath("//Adnotacje/Zwolnienie/P_19N").text).to eq("1")
      expect(doc.at_xpath("//Adnotacje/NoweSrodkiTransportu/P_22N").text).to eq("1")
      expect(doc.at_xpath("//Adnotacje/PMarzy/P_PMarzyN").text).to eq("1")
    end

    it "reads the fixed header attributes from the generated metadata" do
      node = doc.at_xpath("//Naglowek/KodFormularza")
      expect(node.text).to eq("FA")
      expect(node["kodSystemowy"]).to eq("FA (3)")
      expect(node["wersjaSchemy"]).to eq("1-0E")
    end
  end

  # raw_document is provenance, not identity (see {Ksef::FA3::Invoice::IDENTITY}). Without
  # this, a parsed invoice could never equal the one that produced the document.
  describe "identity" do
    # Fully determined: every field the model holds is one the document will carry. A line
    # that leaves `net_amount` to be derived comes back stating it, because `P_11` is in the
    # document — a real difference, pinned by its own example in the parser spec.
    def determined = invoice(lines: [line(net_amount: BigDecimal("1500"))])

    it "ignores the retained document when comparing" do
      built = determined
      parsed = Ksef::FA3.parse(built.to_xml)

      expect(parsed.raw_document).not_to be_nil
      expect(built.raw_document).to be_nil
      expect(parsed).to eq(built)
      expect(parsed.hash).to eq(built.hash)
    end

    # Every member of IDENTITY, one at a time. Pinning inequality on `number` alone let a
    # mutation that dropped `issued_at` from IDENTITY survive the whole suite — equality was
    # thoroughly tested, inequality barely at all.
    it "distinguishes invoices differing in any single identity field" do
      differences = {
        number: "FV/OTHER", issue_date: Date.new(2026, 1, 1), currency: "EUR",
        issued_at: "2020-01-01T00:00:00Z", rounding: :per_summary, invoice_type: "KOR",
        annotations: Ksef::FA3::Invoice::DEFAULT_ANNOTATIONS.merge("P_16" => "1"),
        lines: [line(price: "999")], seller: buyer, buyer: seller,
        correction: Ksef::FA3::Correction.new(
          corrected: Ksef::FA3::CorrectedInvoice.new(number: "FV/2026/01", issue_date: "2026-01-15")
        ),
        totals: Ksef::FA3::Totals.new(gross: "1500.00", buckets: { "P_13_1" => "1500.00" })
      }

      expect(Ksef::FA3::Invoice::IDENTITY).to match_array(differences.keys)
      differences.each do |field, value|
        expect(invoice).not_to eq(invoice(**{ field => value })), "#{field} is not part of identity"
        expect(invoice.hash).not_to eq(invoice(**{ field => value }).hash), "#{field} is not hashed"
      end
    end

    # The `is_a?` guard in Provenance#==: comparing against another Data object is the case
    # worth covering, since member-wise comparison would otherwise be attempted on it.
    it "is not equal to something that is not an invoice" do
      expect(invoice).not_to eq("FV/2026/08/001")
      expect(invoice).not_to eq(invoice.lines.first)
    end

    it "works as a Hash key" do
      table = { determined => :first }

      expect(table[Ksef::FA3.parse(determined.to_xml)]).to be(:first)
    end
  end

  describe "#inspect" do
    # `Data#inspect` would dump the whole XML document into any line that mentions an
    # invoice — including RSpec diffs and exception messages.
    it "redacts the retained document rather than printing it" do
      text = Ksef::FA3.parse(invoice.to_xml).inspect

      expect(text).to include("#<data Ksef::FA3::Invoice", "raw_document=#<Nokogiri::XML::Document (retained)>")
      expect(text).not_to include("Naglowek")
    end

    it "says so plainly when there is no document" do
      expect(invoice.inspect).to include("raw_document=nil")
    end

    it "is what to_s gives too" do
      expect(invoice.to_s).to eq(invoice.inspect)
    end
  end

  describe "#unmapped_elements" do
    it "is empty for an invoice that was built rather than parsed" do
      expect(invoice.unmapped_elements).to eq([])
      expect(invoice).to be_fully_mapped
    end

    it "returns the paths sorted, as documented" do
      xml = invoice.to_xml
                   .sub("<P_2>", "<P_1M>Warszawa</P_1M>\n      <P_2>")
                   .sub("<Adnotacje>", "<P_6>2026-08-01</P_6>\n      <Adnotacje>")
      paths = Ksef::FA3.parse(xml).unmapped_elements

      expect(paths).to eq(paths.sort)
      expect(paths).to eq(["Faktura/Fa/P_1M", "Faktura/Fa/P_6"])
    end

    # It serialises to find out what serialising would lose, so an invoice that cannot be
    # serialised at all has to say that rather than leak the underlying complaint.
    it "explains itself when the invoice cannot be re-serialised" do
      # A NIP that fails its checksum: parse accepts it (§15.3), to_fa3 refuses it.
      parsed = Ksef::FA3.parse(invoice.to_xml.sub("<NIP>1111111111</NIP>", "<NIP>1111111112</NIP>"))

      expect { parsed.unmapped_elements }
        .to raise_error(Ksef::ValidationError, /cannot be re-serialised.*invalid check digit/m)
    end

    it "reports an element the model cannot carry" do
      # `P_1M`, the place of issue: valid FA(3), and not in this model.
      xml = invoice.to_xml.sub("<P_2>", "<P_1M>Warszawa</P_1M>\n      <P_2>")
      parsed = Ksef::FA3.parse(xml)

      expect(parsed.unmapped_elements).to eq(["Faktura/Fa/P_1M"])
      expect(parsed).not_to be_fully_mapped
    end
  end
end
