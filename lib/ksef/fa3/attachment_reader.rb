# frozen_string_literal: true

module Ksef
  module FA3
    # Reads `Zalacznik` into an {Attachment}.
    #
    # Split out for the same reason {RowReader} and {AdvanceReader} are: the attachment is a
    # small tree of its own, and none of it interacts with the invoice's arithmetic.
    #
    # **Nothing here refuses a document.** The parser's contract is that reading a document to
    # find out why KSeF rejected it must work (§7.6), so a block with no `MetaDane` — which the
    # schema forbids — is read as one with none, and {ModelValidator} is what reports it. The
    # models refuse it at construction, so the reader builds them only from what it found.
    module AttachmentReader
      class << self
        include NodeReader

        # @param root [Nokogiri::XML::Node] the `Faktura` element
        # @return [Attachment, nil] nil when the document carries no attachment
        def attachment_from(root)
          node = element(root, "Zalacznik")
          return nil if node.nil?

          Attachment.new(blocks: elements(node, "BlokDanych").map { |block| block_from(block) })
        end

        private

        def block_from(node)
          DataBlock.new(
            heading: text(node, "ZNaglowek"),
            metadata: entries(node, "MetaDane", "ZKlucz", "ZWartosc"),
            # `Tekst` is a wrapper holding 1..10 `Akapit`; the model flattens it, because a
            # wrapper with exactly one possible child carries nothing the paragraphs do not.
            paragraphs: within(node, "Tekst", "Akapit").map(&:text),
            tables: elements(node, "Tabela").map { |table| table_from(table) }
          )
        end

        def table_from(node)
          AttachmentTable.new(
            columns: within(node, "TNaglowek", "Kol").map { |kol| column_from(kol) },
            rows: elements(node, "Wiersz").map { |row| elements(row, "WKom").map(&:text) },
            caption: text(node, "Opis"),
            metadata: entries(node, "TMetaDane", "TKlucz", "TWartosc"),
            totals: totals_from(node)
          )
        end

        # `Typ` is required by the schema, so a column without one is a document defect rather
        # than a shape the model must hold — and {TableColumn} refuses it by name.
        def column_from(node)
          TableColumn.new(name: text(node, "NKom"), type: node["Typ"])
        end

        # nil, not `[]`: `Suma` is `minOccurs="0"`, and a table with no summary row must not
        # re-serialise with an empty one.
        def totals_from(node)
          suma = element(node, "Suma")
          suma && elements(suma, "SKom").map(&:text)
        end

        # A wrapper element the schema requires may still be absent in a document this parser
        # is being used to *diagnose*, and `elements(nil, …)` would raise `NoMethodError` from
        # inside the gem rather than reporting anything. Absent wrapper, no children.
        def within(node, wrapper, child)
          parent = element(node, wrapper)
          parent.nil? ? [] : elements(parent, child)
        end

        def entries(node, wrapper, key_element, value_element)
          elements(node, wrapper).map do |entry|
            MetaEntry.new(key: text(entry, key_element), value: text(entry, value_element))
          end
        end
      end
    end
  end
end
