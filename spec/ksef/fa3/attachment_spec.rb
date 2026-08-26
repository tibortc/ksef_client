# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/fa3_corpus"

# The invoice attachment (`Zalacznik`) — DESIGN.md §7.4, `docs/REFERENCE.md` §16.
#
# The node is descriptive: it sits beside `Fa` rather than inside it, so nothing here touches a
# summary. What is worth testing is the shapes the schema permits that a naive model would get
# wrong — ragged rows, empty cells, repeated metadata keys — and the invariants that make an
# unserialisable attachment impossible to construct.
RSpec.describe Ksef::FA3::Attachment do
  def column(name, type) = Ksef::FA3::TableColumn.new(name: name, type: type)

  # A minimal valid invoice, so every example below differs only in its attachment.
  def built_with(attachment:)
    Ksef::FA3.build do |f|
      f.number "FV/2026/08/901"
      f.issue_date "2026-08-26"
      f.seller nip: "1111111111", name: "Sprzedawca", address: "ul. A 1, 00-001 Warszawa"
      f.buyer nip: "2222222222", name: "Nabywca", address: "ul. B 2, 00-002 Warszawa"
      f.line name: "Energia", quantity: 1, net_unit_price: "100.00", vat_rate: "23"
      f.attachment attachment unless attachment.nil?
    end
  end

  let(:table) do
    Ksef::FA3::AttachmentTable.new(
      columns: [column("Licznik", "txt"), column("Ilość", "int")],
      rows: [["Licznik nr 9"], ["całodobowa", "20"]]
    )
  end

  describe Ksef::FA3::TableColumn do
    # The payoff from teaching the codegen about inline attribute enumerations: this list is
    # read from the schema, not typed here (`docs/REFERENCE.md` §18.2).
    it "takes its permitted types from the generated metadata" do
      expect(described_class.types).to eq(%w[date datetime dec int time txt])
    end

    it "refuses a type the schema does not permit, naming the ones it does" do
      expect { column("X", "money") }
        .to raise_error(Ksef::ValidationError, /not one FA\(3\) permits.*date, datetime, dec, int, time, txt/m)
    end

    # `NKom` is `TZnakowy2`, whose minLength is 0 — a table whose first column labels its rows
    # commonly has no heading for it.
    it "permits an empty heading" do
      expect(column(nil, "txt").name).to eq("")
    end
  end

  describe Ksef::FA3::MetaEntry do
    it "refuses an entry missing either half" do
      expect { described_class.new(key: "K", value: nil) }.to raise_error(Ksef::ValidationError)
      expect { described_class.new(key: "", value: "V") }.to raise_error(Ksef::ValidationError)
    end

    it "writes under the element names it is given, since MetaDane and TMetaDane share a shape" do
      entry = described_class.new(key: "K", value: "V")

      expect(entry.to_fa3(key_element: "TKlucz", value_element: "TWartosc"))
        .to eq("TKlucz" => "K", "TWartosc" => "V")
    end
  end

  describe Ksef::FA3::AttachmentTable do
    # `Kol` and `WKom` each repeat 1..20 and the schema relates them nowhere. Both Ministry
    # samples exercise it: a one-cell row heads a group of nine-cell ones.
    it "keeps rows ragged rather than padding them to the column count" do
      expect(table.rows).to eq([["Licznik nr 9"], %w[całodobowa 20]])
    end

    it "keeps an empty cell, because TZnakowy2 permits one and a dropped cell shifts a row" do
      totals = described_class.new(columns: [column("A", "txt")], rows: [["x"]], totals: ["", "20"])

      expect(totals.totals).to eq(["", "20"])
    end

    it "distinguishes no summary row from an empty one" do
      expect(table.totals).to be_nil
      expect(table.to_fa3).not_to have_key("Suma")
    end

    # `WKom` is minOccurs=1 within `Wiersz`: a cell may be empty, a row may not have none.
    it "refuses a row with no cells at all" do
      expect { described_class.new(columns: [column("A", "txt")], rows: [[]]) }
        .to raise_error(Ksef::ValidationError, /at least one cell/)
    end

    # A one-row table is common enough that wrapping it twice is noise.
    it "accepts a single row passed flat" do
      flat = described_class.new(columns: [column("A", "txt")], rows: %w[one two])

      expect(flat.rows).to eq([%w[one two]])
    end

    it "refuses a table with no column or no row" do
      expect { described_class.new(columns: [], rows: [["x"]]) }
        .to raise_error(Ksef::ValidationError, /at least one column/)
      expect { described_class.new(columns: [column("A", "txt")], rows: []) }
        .to raise_error(Ksef::ValidationError, /at least one row/)
    end
  end

  describe Ksef::FA3::DataBlock do
    it "refuses a block that states no metadata, which the schema requires" do
      expect { described_class.new(metadata: {}) }
        .to raise_error(Ksef::ValidationError, /at least one metadata entry/)
    end

    it "refuses more paragraphs than Akapit permits" do
      expect { described_class.new(metadata: { "K" => "V" }, paragraphs: Array.new(11) { "p" }) }
        .to raise_error(Ksef::ValidationError, /at most 10/)
    end

    # A Hash is sugar for building. Parsing never produces one, because the schema permits a
    # repeated key and a Hash cannot hold it.
    it "accepts a Hash and stores ordered pairs" do
      block = described_class.new(metadata: { "B" => "2", "A" => "1" })

      expect(block.metadata.map(&:key)).to eq(%w[B A])
      expect(block.to_h_metadata).to eq("B" => "2", "A" => "1")
    end

    it "keeps a repeated key, which a Hash would lose" do
      pairs = [Ksef::FA3::MetaEntry.new(key: "Okres", value: "od"),
               Ksef::FA3::MetaEntry.new(key: "Okres", value: "do")]
      block = described_class.new(metadata: pairs)

      expect(block.metadata.size).to eq(2)
      expect(block.to_h_metadata.size).to eq(1)
    end

    it "omits Tekst entirely when there are no paragraphs" do
      expect(described_class.new(metadata: { "K" => "V" }).to_fa3).not_to have_key("Tekst")
    end
  end

  describe "the attachment node" do
    # `Builder#attachment` takes either, so both arms are reachable from the DSL.
    it "wraps blocks, and passes an attachment through unchanged" do
      block = Ksef::FA3::DataBlock.new(metadata: { "K" => "V" })
      already = described_class.new(blocks: block)

      expect(described_class.wrap(block)).to eq(already)
      expect(described_class.wrap(already)).to equal(already)
    end

    it "refuses an attachment with no block" do
      expect { described_class.new(blocks: []) }
        .to raise_error(Ksef::ValidationError, /at least one data block/)
    end
  end

  describe "on an invoice" do
    let(:invoice) do
      Ksef::FA3.build do |f|
        f.number "FV/2026/08/900"
        f.issue_date "2026-08-26"
        f.seller nip: "1111111111", name: "Sprzedawca", address: "ul. A 1, 00-001 Warszawa"
        f.buyer nip: "2222222222", name: "Nabywca", address: "ul. B 2, 00-002 Warszawa"
        f.line name: "Energia", quantity: 1, net_unit_price: "100.00", vat_rate: "23"
        f.attachment Ksef::FA3::DataBlock.new(
          metadata: { "Kod PPE" => "999999999999999999" },
          heading: "Rozliczenie", paragraphs: %w[Pierwszy Drugi], tables: table
        )
      end
    end

    it "writes Zalacznik as a sibling of Fa, not a child of it" do
      root = Nokogiri::XML(invoice.to_xml).remove_namespaces!.root

      expect(root.element_children.map(&:name)).to end_with("Fa", "Zalacznik")
    end

    it "validates against the pinned XSD" do
      expect(Ksef::FA3::Validator.errors_for(invoice.to_xml)).to be_empty
    end

    it "round-trips" do
      expect(Ksef::FA3.parse(invoice.to_xml).attachment).to eq(invoice.attachment)
    end

    it "writes the column type as an attribute alongside its nested heading" do
      kol = Nokogiri::XML(invoice.to_xml).remove_namespaces!.at_xpath("//Kol")

      expect(kol["Typ"]).to eq("txt")
      expect(kol.at_xpath("NKom").text).to eq("Licznik")
    end

    it "is absent from a document that carries none" do
      expect(invoice.with(attachment: nil).to_xml).not_to include("Zalacznik")
    end
  end

  # The two Ministry samples that carry one. Their attachment paths were the last 17 entries in
  # `#unmapped_elements`; that set going empty is what "the attachment is modelled" means.
  # Tier 1a knew nothing about the attachment until an audit found `#errors` **raising** on it
  # — `NoMethodError` for a value that is not an Attachment, and a bare `ArgumentError` out of
  # libxml2 for a U+0000 anywhere in its nine text fields. Both broke CLAUDE.md's "#errors
  # reports rather than raises", and the second escaped this gem's error hierarchy entirely.
  describe "tier 1a" do
    let(:invoice) { built_with(attachment: nil) }

    def with_attachment(value) = invoice.with(attachment: value)

    def one_table(**over)
      Ksef::FA3::AttachmentTable.new(
        columns: over[:columns] || [column("A", "txt")], rows: over[:rows] || [["cell"]],
        totals: over[:totals], caption: over[:caption]
      )
    end

    def one_block(**over)
      described_class.new(blocks: Ksef::FA3::DataBlock.new(
        metadata: over[:metadata] || { "K" => "V" }, heading: over[:heading],
        paragraphs: over.fetch(:paragraphs, []), tables: over[:tables] || one_table
      ))
    end

    # `Invoice#initialize` wraps, so junk becomes a junk *block* rather than a junk attachment
    # — and tier 1a names which block, which is the more useful message.
    it "reports junk as a bad block instead of raising NoMethodError" do
      expect(with_attachment("junk").errors.map(&:field)).to eq(["attachment.blocks[0]"])
      expect(with_attachment([1]).errors.first.message).to include("not a Ksef::FA3::DataBlock")
    end

    # The guard `FieldChecks` already had, which the attachment never reached. Every one of
    # these raised `ArgumentError: string contains null byte` before.
    # Built inside the example, because the helpers only exist there.
    %i[cell heading metadata caption column_heading paragraph summary_cell].each do |where|
      it "reports a NUL byte in a #{where.to_s.tr("_", " ")} with its field path, rather than raising" do
        nul = "a#{0.chr}b"
        attachment = case where
                     when :cell then one_block(tables: one_table(rows: [[nul]]))
                     when :heading then one_block(heading: nul)
                     when :metadata then one_block(metadata: { "K" => nul })
                     when :caption then one_block(tables: one_table(caption: nul))
                     when :column_heading then one_block(tables: one_table(columns: [column(nul, "txt")]))
                     when :paragraph then one_block(paragraphs: [nul])
                     else one_block(tables: one_table(totals: [nul]))
                     end
        issues = with_attachment(attachment).errors

        expect(issues.map(&:message)).to include(/U\+0000/)
        expect(issues.first.field).to start_with("attachment.blocks[0]")
      end
    end

    it "addresses a nested field precisely enough to find it" do
      deep = one_block(tables: one_table(rows: [["fine"], ["x" * 300]]))

      expect(with_attachment(deep).errors.map(&:field))
        .to eq(["attachment.blocks[0].tables[0].rows[1][0]"])
    end

    it "reports non-UTF-8 attachment text as such, not as an unreadable document" do
      latin = one_block(metadata: { "K" => "Łódź".encode("Windows-1250") })

      expect(with_attachment(latin).errors.first.message).to include("Windows-1250")
    end

    # `Suma` is optional but `SKom` is not, so an empty totals list emits an empty element the
    # XSD rejects. Its three siblings are refused at construction; this one reached libxml2.
    it "reports an empty summary row rather than emitting an empty Suma" do
      expect(with_attachment(one_block(tables: one_table(totals: []))).errors.map(&:field))
        .to eq(["attachment.blocks[0].tables[0].totals"])
    end

    it "reports an empty paragraph, which TZnakowy512 forbids" do
      expect(with_attachment(one_block(paragraphs: [""])).errors.map(&:field))
        .to eq(["attachment.blocks[0].paragraphs[0]"])
    end

    # The collections are wrapped, not type-checked, at construction — so a stray value reaches
    # tier 1a and must be named rather than crashing the serializer.
    # The collections are wrapped, not type-checked, at construction — so a stray value reaches
    # tier 1a and must be named rather than crashing the serializer.
    %i[block metadata_entry table column].each do |what|
      it "names a #{what.to_s.tr("_", " ")} that is not the value object it should be" do
        attachment = case what
                     when :block then described_class.new(blocks: ["junk"])
                     when :metadata_entry
                       described_class.new(blocks: Ksef::FA3::DataBlock.new(metadata: ["junk"]))
                     when :table
                       described_class.new(blocks: Ksef::FA3::DataBlock.new(
                         metadata: { "K" => "V" }, tables: ["junk"]
                       ))
                     else
                       described_class.new(blocks: Ksef::FA3::DataBlock.new(
                         metadata: { "K" => "V" },
                         tables: Ksef::FA3::AttachmentTable.new(columns: ["junk"], rows: [["x"]])
                       ))
                     end

        expect(with_attachment(attachment).errors.map(&:message).first).to include("is not a Ksef::FA3::")
      end
    end

    # An empty cell is legal — `TZnakowy2` has minLength 0 — and must not be reported as one of
    # the empties above.
    it "says nothing about an empty cell or an empty column heading" do
      fine = one_block(tables: one_table(columns: [column("", "txt")], rows: [["", "x"]]))

      expect(with_attachment(fine).errors).to be_empty
    end

    it "leaves the Ministry's own attachments unreported" do
      parsed = Ksef::FA3.parse(FA3Corpus.read("mf-samples/przyklad-24.xml"))

      expect(parsed.errors).to be_empty
    end
  end

  # An invoice carrying an attachment is allowed 3 MB rather than 1 MB (`docs/REFERENCE.md`
  # §6.2). Tier 1b defaulted to 1 MB for every document, so the change that made attachments
  # representable also made a legal attachment invoice unsendable.
  describe "the size ceiling" do
    it "allows an attachment invoice past one megabyte" do
      readings = Array.new(20) { |n| Ksef::FA3::MetaEntry.new(key: "Odczyt #{n}", value: "x" * 250) }
      bulky = built_with(attachment: described_class.new(
        blocks: Array.new(200) { Ksef::FA3::DataBlock.new(metadata: readings) }
      ))

      expect(bulky.to_xml.bytesize).to be > Ksef::FA3::DocumentValidator::MAX_BYTES
      expect(bulky.errors).to be_empty
    end

    it "still holds an invoice with no attachment to one megabyte" do
      expect(Ksef::FA3::DocumentValidator.default_max_bytes(attachment: false))
        .to eq(Ksef::FA3::DocumentValidator::MAX_BYTES)
    end
  end

  # Gaps a mutation audit found on 2026-08-26: eight of thirty-eight mutations survived a suite
  # with 100% line, branch and method coverage of this code. Coverage was measuring
  # reachability, not constraint.
  describe "shapes nothing exercised" do
    # **The corpus has one block per attachment**, so `blocks.first` anywhere — in the reader or
    # the serializer — silently dropped every block after it, invisibly to the XSD (one block is
    # valid), to `#unmapped_elements` (identical paths) and to `#errors`.
    it "keeps every block through a round trip, not just the first" do
      two = built_with(attachment: described_class.new(blocks: [
                                                         Ksef::FA3::DataBlock.new(metadata: { "Pierwszy" => "1" },
                                                                                  tables: table),
                                                         Ksef::FA3::DataBlock.new(metadata: { "Drugi" => "2" },
                                                                                  paragraphs: "Uwaga")
                                                       ]))

      # The attachment, not the whole invoice: `net_amount` and `issued_at` come back derived
      # and generated respectively, which is §17.3's known asymmetry and not this node's.
      expect(Ksef::FA3.parse(two.to_xml).attachment.blocks.map { |b| b.metadata.first.key })
        .to eq(%w[Pierwszy Drugi])
      expect(Ksef::FA3.parse(two.to_xml).attachment).to eq(two.attachment)
    end

    # `cells`' `.to_s` is what normalises nil, and the only value it changes is nil — which no
    # corpus document and no other example supplies. Without it the invoice stops equalling
    # itself, with every diagnostic silent.
    it "normalises a nil cell, which would otherwise break the round-trip law" do
      ragged = Ksef::FA3::AttachmentTable.new(columns: [column("A", "txt")], rows: [["x", nil, "y"]])
      invoice = built_with(attachment: Ksef::FA3::DataBlock.new(metadata: { "K" => "V" }, tables: ragged))

      expect(ragged.rows).to eq([["x", "", "y"]])
      expect(Ksef::FA3.parse(invoice.to_xml).attachment).to eq(invoice.attachment)
    end

    # The refusing side was tested; the accepting side was not, so `>` becoming `>=` refused the
    # maximum FA(3) permits and nothing noticed.
    it "accepts exactly the ten paragraphs Akapit permits" do
      block = Ksef::FA3::DataBlock.new(metadata: { "K" => "V" }, paragraphs: Array.new(10) { |n| "p#{n}" })

      expect(block.paragraphs.size).to eq(10)
      expect(built_with(attachment: block).errors).to be_empty
    end

    # Asserting the six values as a literal is satisfied by a hardcoded constant — the exact
    # thing reading them from the schema exists to prevent (`docs/REFERENCE.md` §18.2).
    it "takes the column types from the generated metadata, not from a constant here" do
      declared = Ksef::FA3::Generated::Types::ALL
                 .fetch("Faktura/Zalacznik/BlokDanych/Tabela/TNaglowek/Kol")[:attributes]
                 .find { |attribute| attribute[:name] == "Typ" }
                 .fetch(:values)

      expect(Ksef::FA3::TableColumn.types).to equal(declared)
    end

    it "accepts the documented convenience forms" do
      bare = Ksef::FA3::AttachmentTable.new(columns: column("A", "txt"), rows: [["x"]])

      expect(bare.columns.size).to eq(1)
      expect(bare.metadata).to be_empty
    end

    # `Correction.wrap` hands back the caller's own Array, so freezing it in place made their
    # next `<<` raise from somewhere they never called.
    it "does not freeze an array the caller still holds" do
      entries = [Ksef::FA3::MetaEntry.new(key: "A", value: "1")]
      Ksef::FA3::DataBlock.new(metadata: entries)

      expect { entries << Ksef::FA3::MetaEntry.new(key: "B", value: "2") }.not_to raise_error
    end
  end

  describe "the Ministry's samples" do
    %w[24 25].each do |number|
      context "with przyklad-#{number}" do
        let(:parsed) { Ksef::FA3.parse(FA3Corpus.read("mf-samples/przyklad-#{number}.xml")) }

        it "reads the attachment" do
          block = parsed.attachment.blocks.first

          expect(parsed.attachment.blocks.size).to eq(1)
          expect(block.metadata.size).to eq(8)
          expect(block.tables.size).to eq(3)
        end

        it "reads a ragged table, keeping the one-cell row the document states" do
          widths = parsed.attachment.blocks.first.tables.first.rows.map(&:size)

          expect(widths).to eq([1, 9])
        end

        it "leaves no attachment element unmapped" do
          expect(parsed.unmapped_elements.grep(/Zalacznik/)).to be_empty
        end
      end
    end
  end
end
