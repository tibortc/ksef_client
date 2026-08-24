# frozen_string_literal: true

RSpec.describe Ksef::FA3::Parser do
  # A minimal invoice built through the public DSL, so a builder change fails here too.
  #
  # `issued_at` and `net_amount` are set explicitly, which makes this invoice **fully
  # determined** — every field the model holds is one the document will carry. Leave either
  # out and the round trip cannot be an equality, for reasons that are properties of the
  # model rather than of the parser; both cases are pinned by their own examples below.
  def built(**overrides)
    Ksef::FA3.build do |f|
      f.seller nip: "9999999999", name: "ACME sp. z o.o.",
               address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001" }
      f.buyer nip: "1111111111", name: "Klient S.A.", address: { line1: "Długa 2, 30-001 Kraków" }
      f.number overrides.fetch(:number, "FV/2026/08/001")
      f.issue_date Date.new(2026, 8, 24)
      f.issued_at "2026-08-24T09:00:00Z"
      f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23",
             net_amount: 1500
    end
  end

  # Wraps the given parts in a well-formed FA(3) envelope, for the cases that need a
  # document the builder cannot produce. Variadic so call sites pass parts rather than
  # concatenating them.
  def document(*parts)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Faktura xmlns="#{Ksef::FA3::Serializer::NAMESPACE}">
        <Naglowek>
          <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
          <WariantFormularza>3</WariantFormularza>
          <DataWytworzeniaFa>2026-08-24T10:00:00Z</DataWytworzeniaFa>
        </Naglowek>
        #{parts.join}
      </Faktura>
    XML
  end

  def subjects(buyer_identity: "<NIP>1111111111</NIP><Nazwa>Klient S.A.</Nazwa>")
    <<~XML
      <Podmiot1>
        <DaneIdentyfikacyjne><NIP>9999999999</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne>
        <Adres><KodKraju>PL</KodKraju><AdresL1>Prosta 1</AdresL1></Adres>
      </Podmiot1>
      <Podmiot2>
        <DaneIdentyfikacyjne>#{buyer_identity}</DaneIdentyfikacyjne>
        <Adres><KodKraju>PL</KodKraju><AdresL1>Długa 2</AdresL1></Adres>
        <JST>2</JST><GV>2</GV>
      </Podmiot2>
    XML
  end

  def fa(*body) = "<Fa><KodWaluty>PLN</KodWaluty><P_1>2026-08-24</P_1><P_2>FV/1</P_2>#{body.join}</Fa>"

  def one_row(overrides = {})
    row = { "NrWierszaFa" => 1, "P_7" => "Item", "P_8A" => "szt.", "P_8B" => "1",
            "P_9A" => "100.00", "P_11" => "100.00", "P_12" => "23" }.merge(overrides)
    "<FaWiersz>#{row.compact.map { |k, v| "<#{k}>#{v}</#{k}>" }.join}</FaWiersz>"
  end

  describe "reading a document this gem wrote" do
    it "recovers the invoice's own fields" do
      parsed = described_class.parse(built.to_xml)

      expect(parsed).to have_attributes(
        number: "FV/2026/08/001", issue_date: Date.new(2026, 8, 24),
        currency: "PLN", invoice_type: "VAT"
      )
    end

    it "recovers the parties and the lines" do
      parsed = described_class.parse(built.to_xml)

      expect(parsed.seller.nip).to eq("9999999999")
      expect(parsed.buyer.name).to eq("Klient S.A.")
      expect(parsed.lines.map(&:name)).to eq(["Consulting"])
    end

    # DESIGN.md §7.6's round-trip law, in its strongest testable form: re-serialising a
    # parsed document reproduces it **byte for byte**. This is the property that actually
    # protects a caller — it says the round trip does not drift — and unlike model equality
    # it holds whether or not the invoice is fully determined.
    it "re-serialises a document it parsed byte for byte" do
      xml = built.to_xml

      expect(described_class.parse(xml).to_xml).to eq(xml)
    end

    # And for a fully determined invoice the law is an outright equality. That only works
    # because raw_document is excluded from identity (see {Ksef::FA3::Invoice::IDENTITY});
    # with it in, the parsed invoice could never equal the built one.
    it "produces an invoice equal to the one that wrote it" do
      invoice = built

      expect(described_class.parse(invoice.to_xml)).to eq(invoice)
      expect(described_class.parse(invoice.to_xml).hash).to eq(invoice.hash)
    end

    # `issued_at: nil` does not mean "no timestamp" — it means "stamp it when you
    # serialise". The document then carries a value the model never held, so the invoice
    # cannot come back equal. Worth pinning, because it would otherwise look like a parser
    # bug and be "fixed" by parsing the timestamp into something lossier.
    it "cannot return an equal invoice when the timestamp was left to serialisation" do
      undetermined = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "ACME", address: { line1: "Prosta 1" }
        f.buyer nip: "1111111111", name: "Klient", address: { line1: "Długa 2" }
        f.number "FV/1"
        f.issue_date Date.new(2026, 8, 24)
        f.line name: "X", qty: 1, unit: "szt.", net_unit_price: 100, vat: "23"
      end
      parsed = described_class.parse(undetermined.to_xml)

      expect(parsed).not_to eq(undetermined)
      expect(parsed.issued_at).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(undetermined.issued_at).to be_nil
      # The byte-level law still holds, which is the point of preferring it.
      expect(parsed.to_xml).to eq(described_class.parse(parsed.to_xml).to_xml)
    end

    # The other half of the same distinction: a line that derives its net from quantity ×
    # price is not the same model as one that states it, even when both compute to 1500.
    it "returns a line that states its net, where the source line derived it" do
      derived = Ksef::FA3::Line.new(name: "X", quantity: 10, unit: "godz.",
                                    net_unit_price: 150, vat_rate: "23")
      parsed = described_class.parse(built.to_xml).lines.first

      expect(parsed.net).to eq(derived.net)
      expect(parsed.net_amount).to eq(BigDecimal("1500"))
      expect(derived.net_amount).to be_nil
    end

    it "takes the net value from P_11 rather than recomputing it" do
      # 20 × 1000 ≠ 18000: a discounted line, which upstream's own corpus contains. A
      # parser that recomputed would silently restate the invoice.
      xml = document(subjects, fa(one_row("P_8B" => "20", "P_9A" => "1000.00", "P_11" => "18000.00"),
                                  "<P_13_1>18000.00</P_13_1><P_14_1>4140.00</P_14_1><P_15>22140.00</P_15>",
                                  "<RodzajFaktury>VAT</RodzajFaktury>"))

      expect(described_class.parse(xml).lines.first.net).to eq(BigDecimal("18000"))
    end

    it "keeps DataWytworzeniaFa as written, so a round trip does not re-render it" do
      xml = document(subjects, fa(one_row, "<RodzajFaktury>VAT</RodzajFaktury>"))
            .sub("2026-08-24T10:00:00Z", "2026-08-24T12:30:00+02:00")

      expect(described_class.parse(xml).to_xml).to include("2026-08-24T12:30:00+02:00")
    end
  end

  describe "the buyer's identity" do
    # TPodmiot2 wraps Nazwa in an `<xsd:sequence minOccurs="0">`, unlike TPodmiot1's plain
    # sequence. Upstream's own corpus has a buyer with a NIP and no name.
    it "accepts a buyer with no Nazwa" do
      xml = document(subjects(buyer_identity: "<NIP>1111111111</NIP>"),
                     fa(one_row, "<RodzajFaktury>VAT</RodzajFaktury>"))
      parsed = described_class.parse(xml)

      expect(parsed.buyer.name).to be_nil
      expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
    end

    it "requires the seller's Nazwa, which its own type makes mandatory" do
      xml = document(<<~SUBJECTS, fa(one_row))
        <Podmiot1>
          <DaneIdentyfikacyjne><NIP>9999999999</NIP></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Prosta 1</AdresL1></Adres>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne><NIP>1111111111</NIP></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Długa 2</AdresL1></Adres>
        </Podmiot2>
      SUBJECTS

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, %r{Podmiot1/DaneIdentyfikacyjne.*<Nazwa>})
    end

    # The other three branches of TPodmiot2's choice. The document is valid; the model is
    # the limitation, and the message has to say so rather than implying bad input.
    it "reports a non-NIP identification as a model limit, not a malformed document" do
      xml = document(subjects(buyer_identity: "<KodUE>DE</KodUE><NrVatUE>123456789</NrVatUE>"),
                     fa(one_row))

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /identified by KodUE, NrVatUE rather than NIP.*document itself is fine/m)
    end

    it "does not check the checksum of a NIP it reads" do
      # 9999999998 fails the check digit. An invoice already in KSeF is a fact whatever its
      # NIP, and only PROD validates the digits at all (docs/REFERENCE.md §15.3).
      xml = document(subjects(buyer_identity: "<NIP>9999999998</NIP>"), fa(one_row))

      expect(described_class.parse(xml).buyer.nip).to eq("9999999998")
    end

    it "reads JST and GV back as booleans" do
      xml = document(<<~SUBJECTS, fa(one_row))
        <Podmiot1>
          <DaneIdentyfikacyjne><NIP>9999999999</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Prosta 1</AdresL1></Adres>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Gmina</Nazwa></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Długa 2</AdresL1></Adres>
          <JST>1</JST><GV>1</GV>
        </Podmiot2>
      SUBJECTS
      buyer = described_class.parse(xml).buyer

      expect(buyer.local_government_unit).to be(true)
      expect(buyer.vat_group_member).to be(true)
    end

    # The seller has no JST/GV element at all, so absent must mean "no" rather than raise.
    it "treats an absent flag as false" do
      expect(described_class.parse(built.to_xml).seller.local_government_unit).to be(false)
    end
  end

  describe "inferring the rounding strategy" do
    # Two lines of 0.005 tax each: rounded per line that is 0.01 + 0.01 = 0.02; summed
    # first it is 0.01. One grosz, and it is the whole reason the strategy is explicit.
    def two_awkward_lines
      one_row("NrWierszaFa" => 1, "P_8B" => "1", "P_9A" => "0.02", "P_11" => "0.02") +
        one_row("NrWierszaFa" => 2, "P_8B" => "1", "P_9A" => "0.02", "P_11" => "0.02")
    end

    it "reads :per_line when the document's summaries were rounded per line" do
      xml = document(subjects, fa(two_awkward_lines,
                                  "<P_13_1>0.04</P_13_1><P_14_1>0.02</P_14_1><P_15>0.06</P_15>"))

      expect(described_class.parse(xml).rounding).to eq(:per_line)
    end

    it "reads :per_summary when only that strategy reproduces them" do
      xml = document(subjects, fa(two_awkward_lines,
                                  "<P_13_1>0.04</P_13_1><P_14_1>0.01</P_14_1><P_15>0.05</P_15>"))

      expect(described_class.parse(xml).rounding).to eq(:per_summary)
    end

    # A document whose summaries reconcile with its lines under neither strategy is a
    # business-rule violation (tier 3), not a parse failure. It exists, possibly in KSeF.
    it "falls back to :per_line when neither strategy reproduces the summaries" do
      xml = document(subjects, fa(two_awkward_lines,
                                  "<P_13_1>0.04</P_13_1><P_14_1>99.99</P_14_1><P_15>100.03</P_15>"))

      expect(described_class.parse(xml).rounding).to eq(:per_line)
    end

    # A mixed invoice: one taxed line and one exempt. The exempt rate has no `P_14_*`
    # element at all (§8.1a), so the comparison has to skip it rather than look for a bucket
    # that does not exist — while still matching on the bucket that does.
    it "ignores rates that have no tax element when matching the summaries" do
      taxed = one_row("NrWierszaFa" => 1, "P_8B" => "1", "P_9A" => "100.00",
                      "P_11" => "100.00", "P_12" => "23")
      exempt = one_row("NrWierszaFa" => 2, "P_8B" => "1", "P_9A" => "50.00",
                       "P_11" => "50.00", "P_12" => "zw")
      summaries = "<P_13_1>100.00</P_13_1><P_14_1>23.00</P_14_1>" \
                  "<P_13_7>50.00</P_13_7><P_15>173.00</P_15>"
      xml = document(subjects, fa(taxed, exempt, summaries))
      parsed = described_class.parse(xml)

      expect(parsed.rounding).to eq(:per_line)
      expect(parsed.vat_total).to eq(BigDecimal("23"))
      expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
    end

    it "defaults to :per_line when the invoice carries no tax bucket at all" do
      xml = document(subjects, fa(one_row("P_12" => "zw"), "<P_13_7>100.00</P_13_7><P_15>100.00</P_15>"))

      expect(described_class.parse(xml).rounding).to eq(:per_line)
    end
  end

  describe "rejecting what it cannot read" do
    it "refuses input that is not XML" do
      expect { described_class.parse("not xml at all") }
        .to raise_error(Ksef::ValidationError, /Not parseable as XML/)
    end

    it "refuses a different document in the right namespace" do
      expect { described_class.parse(%(<Cokolwiek xmlns="#{Ksef::FA3::Serializer::NAMESPACE}"/>)) }
        .to raise_error(Ksef::ValidationError, /Not an FA\(3\) invoice.*got <Cokolwiek>/)
    end

    # An FA(2) document, or a future FA(4): right root, wrong namespace. Silently accepting
    # it would produce a model built from elements that happen to share names.
    it "refuses the right root in the wrong namespace" do
      expect { described_class.parse(%(<Faktura xmlns="http://crd.gov.pl/wzor/2023/06/29/12648/"/>)) }
        .to raise_error(Ksef::ValidationError, /Not an FA\(3\) invoice/)
    end

    it "names the missing element when a mandatory one is absent" do
      expect { described_class.parse(document(subjects)) }
        .to raise_error(Ksef::ValidationError, /Faktura is missing the mandatory <Fa> element/)
    end

    it "refuses an invoice with no rows" do
      expect { described_class.parse(document(subjects, fa(""))) }
        .to raise_error(Ksef::ValidationError, /no FaWiersz rows/)
    end

    # A row stating no price of any kind is not an incomplete priced row — it is the
    # descriptive row of a collective correction (§8.4), and saying "cannot establish its
    # net value" would blame the document for omitting something it never meant to state.
    it "names a row that states no price at all for what it is" do
      xml = document(subjects, fa(one_row("P_11" => nil, "P_9A" => nil)))

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /FaWiersz 1 states no price at all/)
      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /collective correction.*document itself is fine/m)
    end

    it "refuses a row missing P_11 and the quantity too" do
      xml = document(subjects, fa(one_row("P_11" => nil, "P_8B" => nil)))

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /FaWiersz 1 has neither P_11 nor both/)
    end

    it "accepts a row with no P_11 when quantity and unit price are both present" do
      xml = document(subjects, fa(one_row("P_11" => nil)))

      expect(described_class.parse(xml).lines.first.net).to eq(BigDecimal("100"))
    end
  end

  describe "accepting a parsed document back" do
    it "takes a Nokogiri document as readily as a string" do
      parsed = described_class.parse(Nokogiri::XML(built.to_xml))

      expect(parsed.number).to eq("FV/2026/08/001")
    end
  end

  # Every one of these elements is optional in the schema, so a document may legitimately
  # omit it and the parser has to supply the same default the builder would.
  describe "defaults for elements a document may omit" do
    it "assumes PLN when KodWaluty is absent" do
      xml = document(subjects, "<Fa><P_1>2026-08-24</P_1><P_2>FV/1</P_2>#{one_row}</Fa>")

      expect(described_class.parse(xml).currency).to eq("PLN")
    end

    it "assumes a plain VAT invoice when RodzajFaktury is absent" do
      xml = document(subjects, fa(one_row))

      expect(described_class.parse(xml).invoice_type).to eq("VAT")
    end

    it "assumes PL when KodKraju is absent" do
      xml = document(<<~SUBJECTS, fa(one_row))
        <Podmiot1>
          <DaneIdentyfikacyjne><NIP>9999999999</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne>
          <Adres><AdresL1>Prosta 1</AdresL1></Adres>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Klient</Nazwa></DaneIdentyfikacyjne>
          <Adres><AdresL1>Długa 2</AdresL1></Adres>
        </Podmiot2>
      SUBJECTS

      expect(described_class.parse(xml).seller.address.country).to eq("PL")
    end

    it "reads AdresL2 when present and leaves it out when not" do
      xml = document(<<~SUBJECTS, fa(one_row))
        <Podmiot1>
          <DaneIdentyfikacyjne><NIP>9999999999</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Prosta 1</AdresL1><AdresL2>00-001 Warszawa</AdresL2></Adres>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Klient</Nazwa></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Długa 2</AdresL1></Adres>
        </Podmiot2>
      SUBJECTS
      parsed = described_class.parse(xml)

      expect(parsed.seller.address.line2).to eq("00-001 Warszawa")
      expect(parsed.buyer.address.line2).to be_nil
    end

    # NrWierszaFa is how a row identifies itself, so a row that has none has to be described
    # some other way when it is the one being complained about.
    it "describes an unnumbered row rather than naming it" do
      xml = document(subjects, fa(one_row("NrWierszaFa" => nil, "P_11" => nil, "P_9A" => nil)))

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /FaWiersz \(unnumbered\) states no price/)
    end
  end

  describe "a document with no namespace at all" do
    # `Faktura` unqualified is not FA(3): elementFormDefault is `qualified`, so a real
    # document always carries the namespace. Reached through the `&.` on a nil namespace.
    it "is refused, naming the namespace it lacks" do
      expect { described_class.parse("<Faktura><Fa/></Faktura>") }
        .to raise_error(Ksef::ValidationError, /Not an FA\(3\) invoice.*got <Faktura> in nil/)
    end
  end

  # Every one of these is XSD-optional, and requiring them refused documents that are valid
  # FA(3) while calling them malformed (docs/REFERENCE.md §8.2a).
  describe "elements the schema makes optional" do
    it "accepts a row with no P_7 name and omits it again" do
      xml = document(subjects, fa(one_row("P_7" => nil)))
      parsed = described_class.parse(xml)

      expect(parsed.lines.first.name).to be_nil
      expect(parsed.to_xml).not_to include("<P_7")
      expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
    end

    # `Podmiot2/Adres` is minOccurs="0" — "opcjonalne dla przypadków określonych w art. 106e
    # ust. 5 pkt 3", the simplified invoice.
    it "accepts a buyer with no address and omits it again" do
      xml = document(<<~SUBJECTS, fa(one_row))
        <Podmiot1>
          <DaneIdentyfikacyjne><NIP>9999999999</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Prosta 1</AdresL1></Adres>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Klient</Nazwa></DaneIdentyfikacyjne>
        </Podmiot2>
      SUBJECTS
      parsed = described_class.parse(xml)

      expect(parsed.buyer.address).to be_nil
      expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
    end

    it "still requires the seller's address, which its own type makes mandatory" do
      xml = document(<<~SUBJECTS, fa(one_row))
        <Podmiot1>
          <DaneIdentyfikacyjne><NIP>9999999999</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne>
        </Podmiot1>
        <Podmiot2>
          <DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Klient</Nazwa></DaneIdentyfikacyjne>
          <Adres><KodKraju>PL</KodKraju><AdresL1>Długa 2</AdresL1></Adres>
        </Podmiot2>
      SUBJECTS

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /Podmiot1 is missing the mandatory <Adres>/)
    end

    # P_12 is optional too, but unlike a name the model cannot do without it: every summary
    # bucket is chosen by rate code. So the refusal has to say that, not imply bad input.
    it "refuses a row with no P_12, as a model limit rather than a malformed document" do
      xml = document(subjects, fa(one_row("P_12" => nil)))

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /states no P_12 rate code.*document may be valid/m)
    end
  end

  describe "the annotations" do
    def with_annotations(body)
      document(subjects, fa("#{one_row}<Adnotacje>#{body}</Adnotacje><RodzajFaktury>VAT</RodzajFaktury>"))
    end

    def default_annotations(**overrides)
      { "P_16" => "2", "P_17" => "2", "P_18" => "2", "P_18A" => "2",
        "Zwolnienie" => "<P_19N>1</P_19N>", "NoweSrodkiTransportu" => "<P_22N>1</P_22N>",
        "P_23" => "2", "PMarzy" => "<P_PMarzyN>1</P_PMarzyN>" }.merge(overrides)
    end

    # Values are either a flag ("2") or a nested fragment ("<P_19N>1</P_19N>"); both wrap the
    # same way, so there is nothing to branch on.
    def annotations_xml(**overrides)
      default_annotations(**overrides).map { |name, value| "<#{name}>#{value}</#{name}>" }.join
    end

    # These are declarations with tax consequences. Emitting the defaults regardless meant a
    # parsed invoice claiming cash accounting came back denying it — invisibly, since the
    # element paths are identical either way.
    it "carries a declared flag through a round trip" do
      parsed = described_class.parse(with_annotations(annotations_xml("P_16" => "1")))
      out = Nokogiri::XML(parsed.to_xml).remove_namespaces!

      expect(parsed.annotations["P_16"]).to eq("1")
      expect(out.at_xpath("//Adnotacje/P_16").text).to eq("1")
    end

    it "carries a real VAT exemption instead of asserting there is none" do
      exemption = "<P_19>1</P_19><P_19A>art. 43 ust. 1 pkt 26 ustawy</P_19A>"
      parsed = described_class.parse(with_annotations(annotations_xml("Zwolnienie" => exemption)))
      out = Nokogiri::XML(parsed.to_xml).remove_namespaces!

      expect(out.at_xpath("//Zwolnienie/P_19").text).to eq("1")
      expect(out.at_xpath("//Zwolnienie/P_19A").text).to eq("art. 43 ust. 1 pkt 26 ustawy")
      expect(out.at_xpath("//Zwolnienie/P_19N")).to be_nil
      expect(Ksef::FA3::Validator.errors_for(parsed.to_xml)).to be_empty
    end

    it "falls back to the defaults when the element is absent" do
      parsed = described_class.parse(document(subjects, fa(one_row)))

      expect(parsed.annotations).to eq(Ksef::FA3::Invoice::DEFAULT_ANNOTATIONS)
    end
  end

  # Accepting an unmodelled type produced something worse than a refusal: a valid-looking
  # invoice under the original's number with recomputed, sign-flipped totals.
  describe "invoice types this model does not carry" do
    %w[ZAL ROZ UPR KOR_ZAL KOR_ROZ].each do |type|
      it "refuses a #{type} document, explaining that the document is fine" do
        xml = document(subjects, fa("#{one_row}<RodzajFaktury>#{type}</RodzajFaktury>"))

        expect { described_class.parse(xml) }
          .to raise_error(Ksef::ValidationError, /This is a #{type} invoice.*document itself is fine/m)
      end
    end

    it "still accepts an explicit VAT type" do
      xml = document(subjects, fa("#{one_row}<RodzajFaktury>VAT</RodzajFaktury>"))

      expect(described_class.parse(xml).invoice_type).to eq("VAT")
    end
  end

  describe "malformed field text" do
    it "reports an unreadable P_1 as a ValidationError, not a Date::Error" do
      xml = document(subjects, "<Fa><P_1>not-a-date</P_1><P_2>FV/1</P_2>#{one_row}</Fa>")

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /Cannot read "not-a-date" as a date/)
    end

    it "reports unreadable numeric text as a ValidationError, not an ArgumentError" do
      xml = document(subjects, fa(one_row("P_11" => "", "P_9A" => nil, "P_8B" => nil)))

      expect { described_class.parse(xml) }
        .to raise_error(Ksef::ValidationError, /Cannot read "" as a decimal/)
    end

    # Reached only through the rounding inference, which used to raise here — and so refused a
    # document only when it also stated a P_14, which is an odd place to validate rate codes.
    it "parses a row whose rate code the schema does not define" do
      xml = document(subjects, fa(one_row("P_12" => "24"), "<P_13_1>100.00</P_13_1><P_14_1>23.00</P_14_1>"))
      parsed = described_class.parse(xml)

      expect(parsed.lines.first.vat_rate).to eq("24")
      expect { parsed.to_xml }.to raise_error(Ksef::ValidationError, /Unknown VAT rate code "24"/)
    end
  end
end
