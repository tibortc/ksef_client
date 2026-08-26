# frozen_string_literal: true

module Ksef
  module FA3
    # A table inside an attachment data block (`Tabela`).
    #
    # ## Rows are ragged, and that is the document's doing
    #
    # `Kol` repeats 1..20 and `WKom` repeats 1..20, and **the schema ties them together
    # nowhere**. Both of the Ministry's attachment samples exercise the gap: every table has a
    # one-cell row heading a group — *"Licznik rozliczeniowy energii czynnej nr 99999999"* —
    # followed by rows carrying the full nine. Measured widths are `[1, 9]` and `[1, 6]`.
    #
    # So a row is an Array of cells and nothing pads it. Storing rows as a rectangle would have
    # to either invent cells the document does not have or drop the ones it does, and both are
    # {Provenance}'s bug class: a number or a label the model quietly changed.
    #
    # A cell is `TZnakowy2`, whose `minLength` is **0** — an empty cell is legal, and
    # {Formatting.text} keeps `""` distinct from nil so it survives a round trip.
    AttachmentTable = Data.define(:columns, :rows, :caption, :metadata, :totals)

    # Construction, invariants and serialisation for {Ksef::FA3::AttachmentTable}.
    class AttachmentTable
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      NEEDS_COLUMNS = "An attachment table needs at least one column. `Kol` is minOccurs=1 " \
                      "within `TNaglowek`, which is itself mandatory within `Tabela`."
      NEEDS_ROWS = "An attachment table needs at least one row. `Wiersz` is minOccurs=1 " \
                   "within `Tabela`."
      EMPTY_ROW = "An attachment table row needs at least one cell. `WKom` is minOccurs=1 " \
                  "within `Wiersz` — a cell may be *empty*, but a row may not have none."

      # @param columns [TableColumn, Array<TableColumn>] `TNaglowek/Kol`, 1..20
      # @param rows [Array<Array<String>>] `Wiersz/WKom`; each row 1..20 cells, ragged
      # @param caption [String, nil] `Opis`, `TZnakowy512`
      # @param metadata [Hash, Array<MetaEntry>] `TMetaDane`, 0..1000
      # @param totals [Array<String>, nil] `Suma/SKom`, a summary row
      # @raise [Ksef::ValidationError] if it has no column or no row
      def initialize(columns:, rows:, caption: nil, metadata: [], totals: nil)
        heads = Correction.wrap(columns)
        cells = self.class.rows_from(rows)
        self.class.check!(heads, cells)

        super(**self.class.canonical(heads, cells, caption, metadata, totals))
      end

      def self.canonical(columns, rows, caption, metadata, totals)
        {
          columns: columns.dup.freeze,
          rows: rows.map { |row| cells(row) }.freeze,
          caption: Formatting.text(caption),
          metadata: DataBlock.entries(metadata).freeze,
          totals: totals.nil? ? nil : cells(totals)
        }
      end

      # Every one of these is a document the XSD rejects, so the useful moment to say so is
      # construction rather than serialisation.
      def self.check!(columns, rows)
        raise ValidationError, NEEDS_COLUMNS if columns.empty?
        raise ValidationError, NEEDS_ROWS if rows.empty?
        raise ValidationError, EMPTY_ROW if rows.any?(&:empty?)
      end

      # A single row may be passed flat — `rows: %w[a b]` — because a one-row table is common
      # enough that wrapping it twice is noise. An empty list stays empty rather than becoming
      # one empty row, which is what the first version did: `[].first` is not an Array, so it
      # took the flat branch and manufactured a `Wiersz` with no cells.
      def self.rows_from(rows)
        list = Array(rows)
        return [] if list.empty?

        list.first.is_a?(Array) ? list : [list]
      end

      # `to_s`, not `Formatting.text`'s nil: a cell that is absent and a cell that is empty are
      # the same thing to `TZnakowy2`, and a nil in the middle of a row would serialise as a
      # missing element and shorten it.
      def self.cells(row) = Array(row).map { |cell| Formatting.text(cell).to_s }.freeze

      def to_fa3
        {
          "TMetaDane" => metadata.map { |e| e.to_fa3(key_element: "TKlucz", value_element: "TWartosc") },
          "Opis" => caption,
          "TNaglowek" => { "Kol" => columns.map(&:to_fa3) },
          "Wiersz" => rows.map { |row| { "WKom" => row } },
          "Suma" => totals.nil? ? nil : { "SKom" => totals }
        }.compact
      end
    end
  end
end
