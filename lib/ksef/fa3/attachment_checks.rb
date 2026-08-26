# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a's checks on the invoice attachment (`docs/REFERENCE.md` §8.7).
    #
    # Mixed into {ModelValidator}. It exists because the attachment shipped without it and the
    # gap was not cosmetic: `Invoice#attachment` is a public constructor field that tier 1a never
    # looked at, so **`#errors` raised** rather than reported for two shapes — a value that is
    # not an {Attachment} at all (`NoMethodError`), and a U+0000 anywhere in the attachment's
    # nine text fields (a bare `ArgumentError` from libxml2, outside this gem's error
    # hierarchy). {FieldChecks} predicted the second in its own comments; the attachment simply
    # never reached the guard.
    #
    # The contract this restores is CLAUDE.md's: **`#errors` reports rather than raises**, and
    # what tier 1a passes, `#to_xml` can serialise.
    #
    # ## What is deliberately *not* checked
    #
    # **Cell contents against their column's `Typ`.** A column declared `dec` whose cells hold
    # "nie liczba" is XSD-clean, silent to every tier, and stays that way — because rows are
    # ragged by design (§8.7), a cell cannot be reliably associated with a column at all. A
    # one-cell heading row belongs to no column, so the association is undecidable in general
    # rather than merely unimplemented. Recorded here so the next reader does not mistake it for
    # an oversight.
    #
    # **Upper cardinality bounds** — 20 columns, 20 cells, 1000 rows, 1000 blocks. Tier 2
    # reports every one of them against the schema, and restating a bound the XSD already
    # enforces is what DESIGN.md §7.1 forbids.
    module AttachmentChecks
      # Included rather than assumed present: constant lookup is lexical.
      include FieldChecks

      private

      # No `is_a?(Attachment)` guard: {Invoice#initialize} routes the field through
      # {Attachment.wrap}, so this is nil or an {Attachment} and nothing else. Anything odd a
      # caller passes becomes an odd *block*, which {#block_errors} names — and that is the more
      # useful message anyway, because it says which block.
      def attachment_errors(invoice)
        return [] if invoice.attachment.nil?

        indexed(invoice.attachment.blocks, "attachment.blocks") { |block, field| block_errors(block, field) }
      end

      def block_errors(block, field)
        return [wrong_type(field, "DataBlock")] unless block.is_a?(DataBlock)

        [
          *text_errors(block.heading, "#{field}.heading", LONG_TEXT),
          *indexed(block.metadata, "#{field}.metadata") { |entry, at| entry_errors(entry, at) },
          # `Akapit` is `TZnakowy512`, whose minLength is 1 — an empty paragraph is a document
          # the XSD rejects, so `required: true` is right here even though the list is optional.
          *indexed(block.paragraphs, "#{field}.paragraphs") { |p, at| text_errors(p, at, LONG_TEXT, required: true) },
          *indexed(block.tables, "#{field}.tables") { |table, at| table_errors(table, at) }
        ]
      end

      def table_errors(table, field)
        return [wrong_type(field, "AttachmentTable")] unless table.is_a?(AttachmentTable)

        [
          *text_errors(table.caption, "#{field}.caption", LONG_TEXT),
          *indexed(table.metadata, "#{field}.metadata") { |entry, at| entry_errors(entry, at) },
          *indexed(table.columns, "#{field}.columns") { |column, at| column_errors(column, at) },
          *indexed(table.rows, "#{field}.rows") { |row, at| row_errors(row, at) },
          *summary_row_errors(table, field)
        ]
      end

      # `Suma` is optional, but `SKom` is `minOccurs="1"` inside it — so an empty totals list
      # emits an empty `Suma`, which the XSD rejects. Its three sibling emptiness rules are
      # enforced at construction; this one was not, and fell through to a libxml2 message.
      def summary_row_errors(table, field)
        return [] if table.totals.nil?
        return [Issue.new(field: "#{field}.totals", message: "is empty; omit it instead")] if table.totals.empty?

        row_errors(table.totals, "#{field}.totals")
      end

      def row_errors(row, field) = indexed(row, field) { |cell, at| cell_errors(cell, at) }

      # `Typ` is not re-checked here. {TableColumn} refuses a value outside the enumeration at
      # construction, and `Canonical#with` re-runs that constructor — so a `TableColumn` that
      # exists has a legal type, and a tier-1a check for it would be a branch nothing can reach.
      # The enumeration itself comes from the generated metadata either way.
      def column_errors(column, field)
        return [wrong_type(field, "TableColumn")] unless column.is_a?(TableColumn)

        cell_errors(column.name, "#{field}.name")
      end

      def entry_errors(entry, field)
        return [wrong_type(field, "MetaEntry")] unless entry.is_a?(MetaEntry)

        [*text_errors(entry.key, "#{field}.key", SHORT_TEXT, required: true),
         *text_errors(entry.value, "#{field}.value", SHORT_TEXT, required: true)]
      end

      # **A cell is not ordinary text.** `WKom`, `SKom` and `NKom` are `TZnakowy2`, whose
      # `minLength` is **0** — so an empty cell is legal, and it is the one thing
      # {FieldChecks#text_errors} refuses. Everything else it checks still applies, and the
      # forbidden-character half is the reason this module exists at all.
      def cell_errors(value, field)
        return [] if value.nil?

        bad_encoding = encoding_issue(value, field)
        return [bad_encoding] if bad_encoding

        text = collapse(value)
        [forbidden_character_issue(text, field), length_issue(text, field, SHORT_TEXT)].compact
      end

      def indexed(list, prefix)
        list.each_with_index.flat_map { |item, index| yield(item, "#{prefix}[#{index}]") }
      end

      def wrong_type(field, name) = Issue.new(field: field, message: "is not a Ksef::FA3::#{name}")
    end
  end
end
