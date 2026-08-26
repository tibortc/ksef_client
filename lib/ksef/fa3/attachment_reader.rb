# frozen_string_literal: true

module Ksef
  module FA3
    # Reads `Zalacznik` into an {Attachment}.
    #
    # Split out for the same reason {RowReader} and {AdvanceReader} are: the attachment is a
    # small tree of its own, and none of it interacts with the invoice's arithmetic.
    #
    # ## This reader **does** refuse some documents, and that was mis-described
    #
    # An earlier version of this comment claimed "nothing here refuses a document" and named
    # {ModelValidator} as the reporter. Both were false: the models refuse at construction, so
    # eight structurally-invalid attachment shapes raised out of `Ksef::FA3.parse` — taking the
    # whole invoice with them — and tier 1a did not look at the attachment at all. An audit
    # found it on 2026-08-26; the reporter now exists ({AttachmentChecks}) and this says what
    # the code does.
    #
    # **What refuses:** an attachment with no `BlokDanych`, a block with no `MetaDane`, a
    # `MetaDane` missing either half, a table with no `TNaglowek` or no `Wiersz`, a `Wiersz`
    # with no `WKom`, a `Kol` with no `Typ` or a `Typ` outside the enumeration. Each is a
    # document the XSD rejects, and each is a shape the model cannot represent.
    #
    # **Why that is the choice, and what the alternative was.** The parser already refuses a
    # nameless seller and a missing `P_1`, so refusing structurally-impossible input is
    # consistent rather than novel. The alternative — relax the model's invariants so any
    # readable document parses, and let tier 1a report — is coherent and is what
    # {Line#net} did for an unpriced row (§8.6). It was not taken here because the attachment's
    # invariants are cardinality rules the XSD states, not amounts the model would silently
    # alter, so representing them wrongly buys nothing. **The cost is real and worth knowing:**
    # a malformed attachment makes the invoice's tax figures unreadable, and the attachment is
    # the one node with no tax meaning. If that bites someone, relaxing the invariants is the
    # fix, not a rescue here.
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
