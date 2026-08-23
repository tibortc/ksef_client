# frozen_string_literal: true

require "nokogiri"

module Ksef
  module FA3
    # Reads an FA(3) document back into the model (DESIGN.md §7.6).
    #
    # ## The asymmetry with the serializer is the whole design
    #
    # {Serializer} is total: every model it is given becomes a document. The parser cannot
    # be, because FA(3) is far larger than this model. A real invoice carries `Podmiot3`,
    # `PodmiotUpowazniony`, `DaneKontaktowe`, `OkresFa`, `Zalacznik`, correction references,
    # currency-conversion twins of every tax bucket — and 0.1 models a plain `VAT` invoice.
    #
    # So parsing takes what it understands and **keeps the whole document** on
    # {Invoice#raw_document}. Nothing is lost, but nothing is silently invented either:
    # {Invoice#unmapped_elements} names exactly what re-serialisation would drop, which a
    # caller should look at before calling `#to_xml` on a document they did not write.
    # `parse` → `to_xml` is not a safe edit-in-place operation, and that is a property of
    # the model's coverage rather than a bug to fix here.
    #
    # ## Three things it deliberately does not do
    #
    # **It does not recompute what the document states.** `P_11` is read straight into
    # {Line#net_amount} rather than being derived from `P_8B × P_9A`. The two disagree in
    # real documents — upstream's own `invoice-template-fa-3-with-custom-Subject3.xml` has a
    # row of `20 × 1000` whose net is `18000`, because a line may carry a discount — and the
    # document's own figure is the authority. Deriving it would quietly rewrite an invoice.
    #
    # **It does not validate.** A caller who wants that has `Invoice#validate!` (tier 2) and
    # can run it on the result. Parsing a document in order to inspect *why* KSeF rejected
    # it is a normal thing to want, and a parser that refuses invalid input cannot do it.
    #
    # **It does not verify the checksum of a NIP it reads.** {Subject#to_fa3} does that on
    # the way out. Reading is not the moment to reject: an invoice already in KSeF is a fact
    # whatever its NIP, and PROD is the only environment that checks the digits anyway
    # (docs/REFERENCE.md §15.3).
    module Parser
      # FA(3) sets `elementFormDefault="qualified"`, so every element is in the target
      # namespace and unprefixed XPath would match nothing. One prefix, bound once.
      PREFIX = "fa"
      NAMESPACES = { PREFIX => Serializer::NAMESPACE }.freeze

      class << self
        # @param xml [String, Nokogiri::XML::Document]
        # @return [Invoice] with {Invoice#raw_document} set
        # @raise [Ksef::ValidationError] if the input is not a parseable FA(3) invoice, or
        #   uses a construct this model cannot represent at all
        def parse(xml)
          document = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml)
          root = verified_root(document)
          fa_node = require_element(root, "Fa", context: Serializer::ROOT)

          resolve_rounding(build(document, root, fa_node), fa_node)
        end

        private

        def verified_root(document)
          root = document.root
          if root.nil?
            detail = document.errors.first(3).map { |e| "  - #{e.message.strip}" }.join("\n")
            raise ValidationError, "Not parseable as XML:\n#{detail}"
          end

          return root if root.name == Serializer::ROOT && root.namespace&.href == Serializer::NAMESPACE

          raise ValidationError, wrong_document(root)
        end

        # An FA(2) document, or a future FA(4), reaches here: right root name, wrong
        # namespace. Naming both halves matters, because "not an FA(3) invoice" on a file
        # that plainly says `<Faktura>` is baffling without them.
        def wrong_document(root)
          "Not an FA(3) invoice: expected <#{Serializer::ROOT}> in #{Serializer::NAMESPACE}, " \
            "got <#{root.name}> in #{root.namespace&.href.inspect}"
        end

        # Built with `:per_line`, which {#resolve_rounding} then confirms or replaces. The
        # strategy is not a field in the document, so it cannot be read — only inferred from
        # the summaries, and that needs the lines parsed first.
        def build(document, root, fa_node)
          Invoice.new(
            seller: subject_from(require_element(root, "Podmiot1", context: Serializer::ROOT), role: :seller),
            buyer: subject_from(require_element(root, "Podmiot2", context: Serializer::ROOT), role: :buyer),
            number: text!(fa_node, "P_2"),
            issue_date: Date.parse(text!(fa_node, "P_1")),
            lines: lines_from(fa_node),
            currency: text(fa_node, "KodWaluty") || "PLN",
            # Kept as the string it was written as, so a round trip reproduces it byte for
            # byte — {Formatting.date_time} passes a String through untouched. Parsing it
            # into a Time would re-render it, and `+02:00` would come back as `Z`.
            issued_at: text(root, "Naglowek/#{PREFIX}:DataWytworzeniaFa"),
            invoice_type: text(fa_node, "RodzajFaktury") || "VAT",
            rounding: :per_line,
            raw_document: document
          )
        end

        # `role` decides one thing only: whether `Nazwa` is required. `TPodmiot1` makes it
        # mandatory and `TPodmiot2` does not, and upstream's own corpus contains a buyer
        # identified by NIP with no name at all.
        def subject_from(node, role:)
          identity = require_element(node, "DaneIdentyfikacyjne", context: node.name)
          address = require_element(node, "Adres", context: node.name)

          Subject.new(
            nip: identity_nip(identity),
            name: role == :seller ? text!(identity, "Nazwa") : text(identity, "Nazwa"),
            address: Address.new(
              country: text(address, "KodKraju") || "PL",
              line1: text!(address, "AdresL1"),
              line2: text(address, "AdresL2")
            ),
            # Absent means "no" — which is both the schema's meaning for the seller, where
            # neither element exists, and the right default for a buyer that omits them.
            local_government_unit: Formatting.unflag(text(node, "JST")),
            vat_group_member: Formatting.unflag(text(node, "GV"))
          )
        end

        # FA(3) identifies a party by `NIP`, or by `NrVatUE`, or by `NrID`, or by nothing at
        # all for an unidentified buyer. {Subject} holds only a NIP, so the others are a
        # limitation of the model and are reported as one — not as a malformed document,
        # which is what a bare "missing NIP" would imply about a perfectly valid invoice.
        def identity_nip(identity)
          nip = text(identity, "NIP")
          return nip if nip

          alternatives = identity.element_children.map(&:name).reject { |n| n == "Nazwa" }
          raise ValidationError,
                "#{identity.parent.name} is identified by #{alternatives.join(", ")} rather than NIP. " \
                "This model carries a NIP only (DESIGN.md §7.4); the document itself is fine."
        end

        def lines_from(fa_node)
          rows = fa_node.xpath("#{PREFIX}:FaWiersz", NAMESPACES)
          raise ValidationError, "Invoice has no FaWiersz rows" if rows.empty?

          rows.map { |row| line_from(row) }
        end

        def line_from(row)
          net_amount = text(row, "P_11")
          quantity = text(row, "P_8B")
          unit_price = text(row, "P_9A")

          if net_amount.nil? && (quantity.nil? || unit_price.nil?)
            raise ValidationError,
                  "FaWiersz #{text(row, "NrWierszaFa") || "(unnumbered)"} has neither P_11 " \
                  "nor both of P_8B and P_9A, so its net value cannot be established"
          end

          # Passed as the strings they were written as; {Line} converts them, so decimal
          # coercion lives in one place rather than being repeated per caller.
          Line.new(
            name: text!(row, "P_7"), unit: text(row, "P_8A"),
            quantity: quantity, net_unit_price: unit_price,
            vat_rate: text!(row, "P_12"), net_amount: net_amount
          )
        end

        # Delegated to {RoundingInference}: the strategy is not in the document, so it has
        # to be inferred from the summaries — which is reasoning about arithmetic rather
        # than reading elements, and belongs somewhere else.
        def resolve_rounding(invoice, fa_node)
          RoundingInference.apply(
            invoice, RoundingInference.stated_from(fa_node) { |node, name| text(node, name) }
          )
        end

        def require_element(node, name, context:)
          found = node.at_xpath("#{PREFIX}:#{name}", NAMESPACES)
          return found if found

          raise ValidationError, "#{context} is missing the mandatory <#{name}> element"
        end

        def text(node, path)
          found = node.at_xpath("#{PREFIX}:#{path}", NAMESPACES)
          found&.text
        end

        def text!(node, path)
          text(node, path) || raise(ValidationError, "#{label(node)} is missing the mandatory <#{path}> element")
        end

        # `DaneIdentyfikacyjne` appears under both subjects, so the bare element name would
        # not tell a caller which one is wrong. One level of parent is enough to disambiguate
        # every element this parser reads.
        #
        # Every `text!` call site passes a nested element, so there is always a parent — no
        # guard here, because an unreachable branch is worse than a direct expression.
        def label(node) = "#{node.parent.name}/#{node.name}"
      end
    end
  end
end
