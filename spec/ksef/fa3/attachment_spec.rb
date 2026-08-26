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
