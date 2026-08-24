# frozen_string_literal: true

require "nokogiri"
require_relative "../../support/fa3_corpus"

# The `KOR` invoice, end to end: the value objects, the DSL, what gets written, what comes
# back, and what tier 1 says about it (docs/REFERENCE.md §8.4).
RSpec.describe "FA(3) corrections" do
  def seller
    Ksef::FA3::Subject.new(
      nip: "9999999999", name: "ACME sp. z o.o.",
      address: Ksef::FA3::Address.new(street: "Prosta 1", city: "Warszawa", postal_code: "00-001")
    )
  end

  def buyer(**overrides)
    Ksef::FA3::Subject.new(
      nip: "1111111111", name: "Klient S.A.",
      address: Ksef::FA3::Address.new(street: "Długa 2", city: "Kraków", postal_code: "30-001"),
      **overrides
    )
  end

  def corrected(**overrides)
    Ksef::FA3::CorrectedInvoice.new(
      number: "FV/2026/07/010", issue_date: "2026-07-15",
      ksef_number: "5265877635-20250826-0100001AF629-AF", **overrides
    )
  end

  def correction(**overrides)
    Ksef::FA3::Correction.new(corrected: corrected, reason: "obniżka ceny", effect: 3, **overrides)
  end

  def invoice(**overrides)
    Ksef::FA3::Invoice.new(
      seller: seller, buyer: buyer, number: "FK/2026/08/001",
      issue_date: Date.new(2026, 8, 22), issued_at: Time.utc(2026, 8, 22, 10, 0, 0),
      invoice_type: "KOR", correction: correction,
      totals: Ksef::FA3::Totals.new(gross: "-200.00", buckets: { "P_13_1" => "-162.60", "P_14_1" => "-37.40" }),
      **overrides
    )
  end

  def rendered(document) = Nokogiri::XML(document.to_xml).remove_namespaces!

  describe Ksef::FA3::CorrectedInvoice do
    it "canonicalises its date, so a String and the Date it denotes are one object" do
      expect(corrected(issue_date: "2026-07-15")).to eq(corrected(issue_date: Date.new(2026, 7, 15)))
    end

    it "writes the KSeF marker and the number when the corrected invoice is in KSeF" do
      expect(corrected.to_fa3).to eq(
        "DataWystFaKorygowanej" => "2026-07-15",
        "NrFaKorygowanej" => "FV/2026/07/010",
        "NrKSeF" => "1",
        "NrKSeFFaKorygowanej" => "5265877635-20250826-0100001AF629-AF"
      )
    end

    # The other branch of the schema's choice. Modelling it as one nil-able field is what
    # makes emitting both branches, or neither, impossible rather than merely wrong.
    it "writes NrKSeFN instead when the corrected invoice was issued outside KSeF" do
      written = corrected(ksef_number: nil).to_fa3

      expect(written).to include("NrKSeFN" => "1")
      expect(written.keys).not_to include("NrKSeF", "NrKSeFFaKorygowanej")
    end

    it "re-runs the constructor through #with, so 3.2 canonicalises like 4.0" do
      expect(corrected.with(issue_date: "2026-01-02").issue_date).to eq(Date.new(2026, 1, 2))
    end
  end

  describe Ksef::FA3::Correction do
    it "refuses a correction that names no corrected invoice" do
      [[], nil].each do |nothing|
        expect { described_class.new(corrected: nothing) }
          .to raise_error(Ksef::ValidationError, /must name at least one corrected invoice/)
      end
    end

    # `Array(hash)` splats a Hash into pairs, so this was accepted and then raised
    # `NoMethodError` from inside `#to_xml`.
    it "refuses a Hash rather than splatting it into pairs" do
      built = described_class.new(corrected: { number: "FV/1", issue_date: "2026-01-01" })

      expect(built.corrected).to eq([{ number: "FV/1", issue_date: "2026-01-01" }])
      expect(invoice(correction: built).errors.map(&:to_s))
        .to eq(["correction.corrected[0]: is not a Ksef::FA3::CorrectedInvoice"])
    end

    it "does not freeze the array it was given" do
      entries = [corrected]
      described_class.new(corrected: entries)

      expect { entries << corrected }.not_to raise_error
    end

    it "accepts a single corrected invoice without wrapping it in an Array" do
      expect(described_class.new(corrected: corrected).corrected).to eq([corrected])
    end

    # `TypKorekty` restricts xsd:integer, whose value space is integers — so the lexical form
    # is not the value, and "3" from a document must equal 3 from a builder.
    it "canonicalises TypKorekty to an Integer" do
      expect(correction(effect: "3")).to eq(correction(effect: 3))
      expect(correction(effect: 3).effect).to eq(3)
    end

    it "reports an uncoercible TypKorekty as a ValidationError" do
      expect { correction(effect: "later") }
        .to raise_error(Ksef::ValidationError, /Cannot read "later" as a whole number/)
    end

    # `TypKorekty` is minOccurs="0", so nil is a legitimate value and not an omission to
    # default away.
    it "leaves TypKorekty absent when it was never given" do
      bare = described_class.new(corrected: corrected)

      expect(bare.effect).to be_nil
      expect(bare.to_fa3.keys).not_to include("TypKorekty")
    end

    it "re-runs the constructor through #with" do
      expect(correction.with(effect: "2").effect).to eq(2)
    end
  end

  describe Ksef::FA3::Totals do
    it "derives its buckets from the schema rather than restating them" do
      expect(described_class::ELEMENTS).to include("P_13_1", "P_14_1", "P_13_5", "P_14_5", "P_13_11")
    end

    # The `W` twins are the PLN equivalents a foreign-currency invoice carries alongside a
    # bucket. Summing them would double-count the tax.
    it "excludes the currency-conversion twins" do
      expect(described_class::ELEMENTS).not_to include("P_14_1W", "P_14_2W", "P_15", "P_15ZK")
    end

    it "sums nets and taxes separately" do
      totals = described_class.new(gross: "-200.00",
                                   buckets: { "P_13_1" => "-162.60", "P_14_1" => "-37.40", "P_13_7" => "-10.00" })

      expect(totals.net).to eq(BigDecimal("-172.60"))
      expect(totals.vat).to eq(BigDecimal("-37.40"))
    end

    it "answers zero for an invoice that states only P_15" do
      totals = described_class.new(gross: 0)

      expect([totals.net, totals.vat]).to eq([BigDecimal(0), BigDecimal(0)])
    end

    # `Hash#to_h` would keep only the last of two spellings of one element name, dropping a
    # tax base without a word.
    it "refuses one bucket given under two spellings rather than letting one win" do
      # Built through a variable rather than written as a symbol literal: a symbol key is the
      # whole point of the example, and RuboCop's Naming/VariableNumber rejects `:P_13_1`.
      bucket = "P_13_1"
      spelled_twice = { bucket => "-23.00" }.merge(bucket.to_sym => "-100.00")

      expect { described_class.new(gross: "-146.00", buckets: spelled_twice) }
        .to raise_error(Ksef::ValidationError, /"P_13_1" given more than once/)
    end

    it "freezes its buckets, so an invariant cannot be edited around afterwards" do
      expect(described_class.new(gross: 0, buckets: { "P_13_1" => 1 }).buckets).to be_frozen
    end

    it "refuses an element that is not a summary bucket" do
      expect { described_class.new(gross: 0, buckets: { "P_15" => 1 }) }
        .to raise_error(Ksef::ValidationError, /Unknown summary bucket\(s\) "P_15".*passed as gross:/m)
    end

    it "refuses buckets that are not a Hash" do
      expect { described_class.new(gross: 0, buckets: "P_13_1=1") }
        .to raise_error(Ksef::ValidationError, /must be a Hash of element name => amount/)
    end

    # The Float ban applies here as everywhere money flows (DESIGN.md §4.4).
    it "refuses a Float amount" do
      expect { described_class.new(gross: 0, buckets: { "P_13_1" => 1.5 }) }
        .to raise_error(Ksef::ValidationError, /Float is not allowed/)
    end

    it "canonicalises to the scale TKwotowy permits" do
      expect(described_class.new(gross: "1.005").gross).to eq(BigDecimal("1.01"))
    end

    it "re-runs the constructor through #with" do
      expect { described_class.new(gross: 0).with(buckets: { "P_99" => 1 }) }
        .to raise_error(Ksef::ValidationError, /Unknown summary bucket/)
    end
  end

  describe "what a correction writes" do
    let(:document) { rendered(invoice) }

    it "is schema-valid" do
      expect(Ksef::FA3::Validator.errors_for(invoice.to_xml)).to be_empty
    end

    it "states the summary it was given rather than deriving one from its lines" do
      expect(document.at_xpath("//Fa/P_13_1").text).to eq("-162.60")
      expect(document.at_xpath("//Fa/P_14_1").text).to eq("-37.40")
      expect(document.at_xpath("//Fa/P_15").text).to eq("-200.00")
    end

    it "answers the stated figures from #net_total, #vat_total and #gross_total" do
      expect([invoice.net_total, invoice.vat_total, invoice.gross_total])
        .to eq([BigDecimal("-162.60"), BigDecimal("-37.40"), BigDecimal("-200.00")])
    end

    # net_by_rate is keyed by rate code and a stated summary is keyed by bucket; the mapping
    # is not invertible, so the two answer different questions and this one is about lines.
    it "still reports what the lines say, which for a line-less correction is nothing" do
      expect(invoice.net_by_rate).to eq({})
      expect(invoice.vat_by_rate).to eq({})
    end

    it "carries the correction group in schema order" do
      names = document.xpath("//Fa/*").map(&:name)

      expect(names).to include("RodzajFaktury", "PrzyczynaKorekty", "DaneFaKorygowanej")
      expect(names.index("DaneFaKorygowanej")).to be > names.index("RodzajFaktury")
    end

    it "omits the correction group entirely for an ordinary invoice" do
      plain = invoice(invoice_type: "VAT", correction: nil, totals: nil,
                      lines: [Ksef::FA3::Line.new(name: "Consulting", quantity: 1, unit: "szt.",
                                                  net_unit_price: "100", vat_rate: "23")])

      expect(rendered(plain).at_xpath("//Fa/DaneFaKorygowanej")).to be_nil
      expect(plain.gross_total).to eq(BigDecimal("123"))
    end
  end

  describe "an invoice with no lines" do
    it "is allowed when it states its own totals" do
      expect(invoice.lines).to be_empty
    end

    # Without rows *and* without a stated summary there is nothing to compute from, and the
    # result would declare zero tax on an invoice that means to declare some.
    it "is refused when it does not" do
      expect { invoice(totals: nil) }
        .to raise_error(Ksef::ValidationError, /needs at least one line, unless it states its own totals/)
    end

    it "is refused for lines: nil too, rather than raising NoMethodError" do
      expect { invoice(totals: nil, lines: nil) }
        .to raise_error(Ksef::ValidationError, /needs at least one line/)
    end
  end

  describe "the previous state of a party" do
    let(:previous) { buyer(name: "CDE sp. j.", buyer_id: "0001") }
    let(:document) { rendered(invoice(correction: correction(previous_buyers: previous))) }

    it "writes Podmiot2K with its linking key and without JST/GV" do
      node = document.at_xpath("//Fa/Podmiot2K")

      expect(node.at_xpath("DaneIdentyfikacyjne/Nazwa").text).to eq("CDE sp. j.")
      expect(node.at_xpath("IDNabywcy").text).to eq("0001")
      expect(node.xpath("JST | GV")).to be_empty
    end

    it "writes Podmiot1K with the address its type makes mandatory" do
      node = rendered(invoice(correction: correction(previous_seller: seller))).at_xpath("//Fa/Podmiot1K")

      expect(node.at_xpath("DaneIdentyfikacyjne/NIP").text).to eq("9999999999")
      expect(node.at_xpath("Adres/AdresL1").text).to eq("Prosta 1, 00-001 Warszawa")
    end

    it "refuses a previous seller with no address, as it refuses a seller" do
      nameless = Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME sp. z o.o.")

      expect { invoice(correction: correction(previous_seller: nameless)).to_xml }
        .to raise_error(Ksef::ValidationError, /previous_seller \(Podmiot1K\) must have an address/)
    end

    it "lets a previous buyer omit both, as a buyer may" do
      bare = Ksef::FA3::Subject.new(nip: "1111111111")

      expect { invoice(correction: correction(previous_buyers: bare)).to_xml }.not_to raise_error
    end
  end

  describe "the DSL" do
    def built(&block)
      Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: "Prosta 1, 00-001 Warszawa"
        f.buyer nip: "1111111111", name: "Klient S.A.", address: "Długa 2, 30-001 Kraków"
        f.number "FK/2026/08/001"
        f.issue_date Date.new(2026, 8, 22)
        f.invoice_type "KOR"
        block.call(f)
      end
    end

    let(:collective) do
      built do |f|
        f.correction reason: "rabat za pierwsze półrocze", effect: 2, period: "pierwsze półrocze 2026"
        f.corrects number: "FV/2026/01/134", issue_date: "2026-01-15",
                   ksef_number: "5265877635-20250826-0100001AF629-AF"
        f.corrects number: "FV/2026/02/150", issue_date: "2026-02-15"
        f.totals gross: "-50000.00", net: { "23" => "-40650.41" }, vat: { "23" => "-9349.59" }
      end
    end

    it "builds a collective correction that validates" do
      expect(collective.errors).to be_empty
      expect(collective.correction.corrected.size).to eq(2)
      expect(collective.gross_total).to eq(BigDecimal("-50000"))
    end

    it "maps rate codes to summary buckets, since the model stores the buckets" do
      expect(collective.totals.buckets).to eq(
        "P_13_1" => BigDecimal("-40650.41"), "P_14_1" => BigDecimal("-9349.59")
      )
    end

    # Several rate codes share a bucket (§8.1a), so a summary accumulates rather than
    # assigning — the shape of the bug an audit found in DocumentMapping.
    it "accumulates rate codes that share a bucket" do
      invoice = built do |f|
        f.corrects number: "FV/1", issue_date: "2026-01-15"
        f.totals gross: "300.00", net: { "23" => "100.00", "22" => "200.00" }
      end

      expect(invoice.totals.buckets).to eq("P_13_1" => BigDecimal("300.00"))
    end

    it "refuses a VAT amount for a rate code that has no tax bucket" do
      expect do
        built do |f|
          f.corrects number: "FV/1", issue_date: "2026-01-15"
          f.totals gross: "0.00", vat: { "zw" => "0.00" }
        end
      end.to raise_error(Ksef::ValidationError, /has no tax bucket.*Pass it under net: only/m)
    end

    it "needs no explicit correction block when corrects alone says enough" do
      invoice = built do |f|
        f.corrects number: "FV/1", issue_date: "2026-01-15"
        f.totals gross: "0.00"
      end

      expect(invoice.correction.reason).to be_nil
      expect(invoice.correction.corrected.size).to eq(1)
    end

    it "refuses a correction block that names nothing" do
      expect { built { |f| f.correction reason: "bo tak" } }
        .to raise_error(Ksef::ValidationError, /must name at least one corrected invoice/)
    end

    it "reports a misspelled correction key by name" do
      expect { built { |f| f.correction cause: "bo tak" } }
        .to raise_error(Ksef::ValidationError, /Unknown correction option\(s\) :cause/)
    end

    it "reports a misspelled corrects key by name" do
      expect { built { |f| f.corrects nr: "FV/1" } }
        .to raise_error(Ksef::ValidationError, /Unknown corrects option\(s\) :nr/)
    end

    it "leaves an ordinary invoice with no correction at all" do
      plain = Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: "Prosta 1, 00-001 Warszawa"
        f.buyer nip: "1111111111", name: "Klient S.A.", address: "Długa 2, 30-001 Kraków"
        f.number "FV/1"
        f.issue_date Date.new(2026, 8, 22)
        f.line name: "Consulting", qty: 1, unit: "szt.", net_unit_price: 100, vat: "23"
      end

      expect(plain.correction).to be_nil
      expect(plain.totals).to be_nil
    end
  end

  # The Ministry's Przykład 2, written through this gem's own DSL: a price reduction shown as
  # the position before and the position after, in two rows sharing one number.
  describe "before/after rows" do
    def paired
      Ksef::FA3.build do |f|
        f.seller nip: "9999999999", name: "ACME sp. z o.o.", address: "Prosta 1, 00-001 Warszawa"
        f.buyer nip: "1111111111", name: "Klient S.A.", address: "Długa 2, 30-001 Kraków"
        f.number "FK/2026/08/001"
        f.issue_date Date.new(2026, 8, 22)
        f.issued_at "2026-08-22T10:00:00Z"
        f.invoice_type "KOR"
        f.correction reason: "obniżka ceny o 200 zł z uwagi na uszkodzenia estetyczne", effect: 3
        f.corrects number: "FV/2026/02/150", issue_date: "2026-02-15",
                   ksef_number: "5265877635-20250826-0100001AF629-AF"
        # `net_amount` is stated rather than derived, so the built invoice is fully
        # determined and can equal its own parsed form — `P_11` is in the document either way.
        f.line name: "lodówka Zimnotech mk1", qty: 1, unit: "szt.", net_unit_price: "1626.01",
               net_amount: "1626.01", vat: "23", state_before: true
        f.line name: "lodówka Zimnotech mk1", qty: 1, unit: "szt.", net_unit_price: "1463.41",
               net_amount: "1463.41", vat: "23", row_number: 1
        f.totals gross: "-200.00", net: { "23" => "-162.60" }, vat: { "23" => "-37.40" }
      end
    end

    # If this fails, either the serializer changed or the schema did. Regenerate deliberately
    # and read the diff — do not update the fixture to make it pass.
    it "reproduces the approved output byte for byte" do
      golden = File.read(FA3Corpus.path("golden/kor_before_after.xml"), encoding: "UTF-8")

      expect(paired.to_xml).to eq(golden)
    end

    it "marks the before row and leaves the after row unmarked" do
      rows = rendered(paired).xpath("//Fa/FaWiersz")

      expect(rows.map { |row| row.at_xpath("StanPrzed")&.text }).to eq(["1", nil])
    end

    # After UU_ID is dropped, the shared NrWierszaFa is the only thing left pairing the two.
    it "gives the pair the same NrWierszaFa" do
      expect(rendered(paired).xpath("//Fa/FaWiersz/NrWierszaFa").map(&:text)).to eq(%w[1 1])
    end

    it "round-trips to an equal invoice, keeping both the marker and the number" do
      expect(Ksef::FA3.parse(paired.to_xml)).to eq(paired)
    end

    it "is schema-valid" do
      expect(Ksef::FA3::Validator.errors_for(paired.to_xml)).to be_empty
    end
  end

  describe "reading one back" do
    let(:parsed) { Ksef::FA3.parse(invoice.to_xml) }

    # **Every field of the correction, in one object.** An audit on 2026-08-24 nulled each
    # reader in turn and found five that nothing noticed — `period`, `corrected_number`,
    # `previous_seller`, `previous_buyers` and `buyer_id` were asserted on the *write* side
    # only, and the parse-side examples used a correction that carried none of them. A
    # self-round-trip is structurally blind to a reader that never reads a field, because the
    # omission is symmetric; equality against the *built* invoice is not.
    let(:full) do
      invoice(
        correction: correction(
          period: "pierwsze półrocze 2026",
          corrected_number: "FV/2026/07/011",
          previous_seller: seller,
          previous_buyers: [buyer(name: "CDE sp. j.", buyer_id: "0001")],
          corrected: [corrected, corrected(number: "FV/2026/07/012", ksef_number: nil)]
        )
      )
    end

    it "round-trips to an equal invoice" do
      expect(parsed).to eq(invoice)
    end

    it "reads every field of a fully populated correction back" do
      expect(Ksef::FA3.parse(full.to_xml)).to eq(full)
      expect(Ksef::FA3::Validator.errors_for(full.to_xml)).to be_empty
    end

    # Named individually as well, so a failure says which reader broke rather than
    # "not equal" — the equality above is what makes the set exhaustive.
    it "reads each of the five fields no self-round-trip could have caught" do
      read = Ksef::FA3.parse(full.to_xml).correction

      expect(read).to have_attributes(period: "pierwsze półrocze 2026",
                                      corrected_number: "FV/2026/07/011")
      expect(read.previous_seller.name).to eq("ACME sp. z o.o.")
      expect(read.previous_buyers.map(&:buyer_id)).to eq(["0001"])
      expect(read.corrected.map(&:ksef_number).last).to be_nil
    end

    it "reads the summary as stated rather than recomputing it from absent lines" do
      expect(parsed.totals).to eq(invoice.totals)
    end

    # The strategy is not in the document, and for a correction there is nothing to infer
    # from: the summaries were read, not computed.
    it "leaves the rounding strategy at its default rather than inferring one" do
      expect(parsed.rounding).to eq(:per_line)
    end

    # The whole group is minOccurs="0", so a KOR without one is schema-valid and simply has
    # no correction to read. Re-serialising it must not invent one.
    it "reads no correction from a KOR that carries none" do
      bare = Ksef::FA3.parse(invoice.to_xml.sub(%r{<DaneFaKorygowanej>.*</DaneFaKorygowanej>}m, ""))

      expect(bare.correction).to be_nil
      expect(bare.invoice_type).to eq("KOR")
    end

    # The schema's choice is mandatory. Reading only the number treated "the document said
    # neither" as "the document said NrKSeFN", and re-serialising then asserted the corrected
    # invoice had been issued outside KSeF — a declaration nobody made, on valid output.
    it "refuses a DaneFaKorygowanej that states neither branch of the choice" do
      neither = invoice.to_xml.sub(%r{<NrKSeF>1</NrKSeF>\s*<NrKSeFFaKorygowanej>[^<]*</NrKSeFFaKorygowanej>}m, "")

      expect { Ksef::FA3.parse(neither) }
        .to raise_error(Ksef::ValidationError, /states neither NrKSeFFaKorygowanej nor NrKSeFN/)
    end

    it "reads NrKSeFN back as no KSeF number" do
      outside = invoice(correction: correction(corrected: corrected(ksef_number: nil)))

      expect(Ksef::FA3.parse(outside.to_xml).correction.corrected.first.ksef_number).to be_nil
    end
  end

  describe "tier 1 on a correction" do
    it "names a reason that exceeds TZnakowy" do
      issues = invoice(correction: correction(reason: "x" * 257)).errors

      expect(issues.map(&:field)).to include("correction.reason")
      expect(issues.first.message).to include("is 257 characters; the schema allows 256")
    end

    it "names a TypKorekty the schema does not define" do
      expect(invoice(correction: correction(effect: 9)).errors.map(&:to_s))
        .to include(/correction.effect: 9 is not one of TTypKorekty's permitted values/)
    end

    it "names a corrected invoice with no number" do
      broken = correction(corrected: corrected.with(number: nil))

      expect(invoice(correction: broken).errors.map(&:field))
        .to include("correction.corrected[0].number")
    end

    # Tier 2 owns the *format* of a referenced KSeF number, because the only pattern this gem
    # holds is the OpenAPI contract's and the XSD's is wider — see the next example.
    it "leaves a malformed KSeF number to the schema tier, which names the element" do
      broken = correction(corrected: corrected(ksef_number: "not-a-number"))

      expect(invoice(correction: broken).errors.map(&:to_s))
        .to include(/schema:.*NrKSeFFaKorygowanej.*not accepted by the pattern/)
    end

    # The two pinned artifacts genuinely differ (§8.4b): `KsefNumber::FORMAT` comes from the
    # OpenAPI contract, which admits only the NIP issuer form, while `TNumerKSeF` also admits
    # `M\d{9}` and `[A-Z]{3}\d{7}`. Judging a *document* field by the contract's pattern
    # flagged this XSD-valid reference as malformed.
    it "accepts an issuer form the XSD allows and the API contract does not" do
      %w[M123456789-20260815-0100001AF629-AF ABC1234567-20260815-0100001AF629-AF].each do |number|
        sound = invoice(correction: correction(corrected: corrected(ksef_number: number)))

        expect(Ksef::FA3::Validator.errors_for(sound.to_xml)).to be_empty, number
        expect(sound.errors).to be_empty, number
        expect(Ksef::KsefNumber::FORMAT.match?(number)).to be(false), number
      end
    end

    it "still reports a KSeF number that is not readable as UTF-8" do
      broken = correction(corrected: corrected(ksef_number: "5265877635-2025\xFF"))

      expect(invoice(correction: broken).errors.map(&:to_s))
        .to include(/ksef_number: contains bytes that are not valid UTF-8/)
    end

    # §8.4a: all six KSeF numbers in the Ministry's own worked corrections fail §13's CRC-8.
    # They are placeholders, and checking the checksum here would make tier 1 refuse the
    # Ministry's own documents.
    it "does not check the checksum, which the Ministry's own examples fail" do
      placeholder = "9999999999-20230908-8BEF280C8D35-4D"

      expect(Ksef::KsefNumber.valid?(placeholder)).to be(false)
      expect(invoice(correction: correction(corrected: corrected(ksef_number: placeholder))).errors).to be_empty
    end

    it "names a previous buyer whose linking key is too long for IDNabywcy" do
      long = correction(previous_buyers: buyer(buyer_id: "x" * 33))

      expect(invoice(correction: long).errors.map(&:to_s))
        .to include(/correction.previous_buyers\[0\].buyer_id: is 33 characters/)
    end

    it "reports a correction of the wrong class rather than letting to_xml raise" do
      expect(invoice(correction: Object.new).errors.map(&:to_s))
        .to eq(["correction: is not a Ksef::FA3::Correction"])
    end

    it "reports totals of the wrong class rather than letting to_xml raise" do
      expect(invoice(totals: Object.new).errors.map(&:to_s))
        .to eq(["totals: is not a Ksef::FA3::Totals"])
    end

    it "reports a corrected entry of the wrong class" do
      broken = Ksef::FA3::Correction.new(corrected: [Object.new])

      expect(invoice(correction: broken).errors.map(&:to_s))
        .to eq(["correction.corrected[0]: is not a Ksef::FA3::CorrectedInvoice"])
    end

    # The contract tier 1a exists for: what it passes, `#to_xml` can serialise. Reported as
    # an addressed error rather than thrown from the middle of the serializer.
    it "reports an address-less previous seller rather than letting to_xml raise" do
      bare = correction(previous_seller: Ksef::FA3::Subject.new(nip: "9999999999", name: "ACME"))

      expect(invoice(correction: bare).errors.map(&:to_s))
        .to include("correction.previous_seller.address: is required for a previous_seller")
    end

    # `PrzyczynaKorekty` is documented as the reason *"dla faktur korygujących"*, so the
    # group belongs to a correcting type. The XSD cannot say so, which is why tier 1 does.
    it "reports a correction attached to a plain VAT invoice" do
      plain = invoice(invoice_type: "VAT")

      expect(plain.errors.map(&:to_s))
        .to include("correction: is set on a VAT invoice; the correction elements belong to KOR, KOR_ZAL, KOR_ROZ")
      expect(Ksef::FA3::Validator.errors_for(plain.to_xml)).to be_empty
    end

    # The converse is not a rule: the whole group is minOccurs="0", so a KOR that omits it is
    # schema-valid and inventing a complaint would be synthesising a rule (§8.4).
    it "says nothing about a KOR that carries no correction group" do
      expect(invoice(correction: nil).errors).to be_empty
    end

    # The defect three audit lenses found independently on 2026-08-24, and the reason
    # `state_before` is now a tier-1 concern rather than an inert flag on a row.
    describe "a correction whose rows show the state before" do
      def paired_without_totals(**overrides)
        invoice(totals: nil, correction: correction, **overrides,
                lines: [Ksef::FA3::Line.new(name: "Usługa", quantity: 1, unit: "szt.",
                                            net_unit_price: "100.00", net_amount: "100.00",
                                            vat_rate: "23", row_number: 1, state_before: true),
                        Ksef::FA3::Line.new(name: "Usługa", quantity: 1, unit: "szt.",
                                            net_unit_price: "80.00", net_amount: "80.00",
                                            vat_rate: "23", row_number: 1)])
      end

      it "is refused unless it states its totals" do
        expect(paired_without_totals.errors.map(&:to_s))
          .to include(/totals: is required when a line is marked state_before/)
      end

      # What the derived summary would have said, and why it had to be stopped: the
      # before-row is counted as a sale, so a 20.00 refund is declared as a 180.00 charge on
      # a document the XSD accepts.
      it "would otherwise have declared the sum of both states" do
        derived = paired_without_totals

        expect(derived.gross_total).to eq(BigDecimal("221.40"))
        expect(Ksef::FA3::Validator.errors_for(derived.to_xml)).to be_empty
      end

      it "passes once the delta is stated" do
        stated = paired_without_totals(
          totals: Ksef::FA3::Totals.new(gross: "-24.60",
                                        buckets: { "P_13_1" => "-20.00", "P_14_1" => "-4.60" })
        )

        expect(stated.errors).to be_empty
        expect(stated.gross_total).to eq(BigDecimal("-24.60"))
      end

      # Scoped to the marker, not to the type: Przykład 3 is a correction whose single row
      # already *is* the delta, and it computes correctly.
      it "says nothing about a correction whose rows are already deltas" do
        delta = invoice(totals: nil,
                        lines: [Ksef::FA3::Line.new(name: "Usługa", quantity: 1, unit: "szt.",
                                                    net_unit_price: "-162.60", net_amount: "-162.60",
                                                    vat_rate: "23")])

        expect(delta.errors).to be_empty
        expect(delta.gross_total).to eq(BigDecimal("-200.00"))
      end
    end

    it "reports a summary stated on a type that derives one" do
      expect(invoice(invoice_type: "VAT", correction: nil).errors.map(&:to_s))
        .to include(/totals: is set on a VAT invoice, whose summary this model computes/)
    end

    it "passes a well-formed correction" do
      expect(invoice.errors).to be_empty
    end
  end
end
