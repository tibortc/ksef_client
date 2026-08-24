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
      # The invoice kinds {Invoice} can represent faithfully. The other six of
      # `TRodzajFaktury` are DESIGN.md §7.4's remaining work; see {#supported_type!} for why
      # accepting one would be worse than refusing it.
      SUPPORTED_TYPES = %w[VAT].freeze

      class << self
        # Namespace-aware element reading; see {NodeReader}.
        include NodeReader

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
            # Passed as text; {Invoice} converts it, so a malformed date surfaces as a
            # ValidationError rather than as a bare `Date::Error` from outside this gem.
            issue_date: text!(fa_node, "P_1"),
            lines: RowReader.lines_from(fa_node),
            currency: text(fa_node, "KodWaluty") || "PLN",
            # Read, not defaulted. These are declarations with tax consequences — cash
            # accounting, reverse charge, split payment, an actual VAT exemption — and
            # re-emitting the defaults would silently deny every one of them
            # ({Invoice::DEFAULT_ANNOTATIONS}).
            annotations: ElementTree.to_hash(element(fa_node, "Adnotacje")),
            invoice_type: supported_type!(text(fa_node, "RodzajFaktury") || "VAT"),
            # Kept as the string it was written as, so a round trip reproduces it byte for
            # byte — {Formatting.date_time} passes a String through untouched. Parsing it
            # into a Time would re-render it, and `+02:00` would come back as `Z`.
            issued_at: text(root, "Naglowek/DataWytworzeniaFa"),
            rounding: :per_line,
            raw_document: document
          )
        end

        # `role` decides which of `Nazwa` and `Adres` are required: `TPodmiot1` makes both
        # mandatory, `TPodmiot2` makes both optional — the address explicitly *"opcjonalne dla
        # przypadków określonych w art. 106e ust. 5 pkt 3"*, the simplified invoice
        # (docs/REFERENCE.md §8.2a). Requiring them of a buyer rejected valid FA(3).
        def subject_from(node, role:)
          identity = require_element(node, "DaneIdentyfikacyjne", context: node.name)

          Subject.new(
            nip: identity_nip(identity),
            name: role == :seller ? text!(identity, "Nazwa") : text(identity, "Nazwa"),
            address: address_from(node, role: role),
            # Absent means "no" — which is both the schema's meaning for the seller, where
            # neither element exists, and the right default for a buyer that omits them.
            local_government_unit: Formatting.unflag(text(node, "JST")),
            vat_group_member: Formatting.unflag(text(node, "GV"))
          )
        end

        def address_from(node, role:)
          address = element(node, "Adres")
          if address.nil?
            raise ValidationError, "Podmiot1 is missing the mandatory <Adres> element" if role == :seller

            return nil
          end

          Address.new(
            country: text(address, "KodKraju") || "PL",
            line1: text!(address, "AdresL1"),
            line2: text(address, "AdresL2")
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

        # {Invoice} models the plain `VAT` invoice only (DESIGN.md §7.4). Accepting another
        # type produced something far worse than a refusal: a `KOR` parsed and re-serialised
        # kept its `RodzajFaktury` and `P_2` — and therefore KSeF's whole duplicate key
        # (docs/REFERENCE.md §15.2) — while dropping `DaneFaKorygowanej` and recomputing the
        # summaries from rows whose `StanPrzed` marker was ignored. A -9.84 correction came
        # back as a +34.44 invoice, XSD-valid and plausible. Refuse instead.
        def supported_type!(type)
          return type if SUPPORTED_TYPES.include?(type)

          raise ValidationError,
                "This is a #{type} invoice, and only #{SUPPORTED_TYPES.join(", ")} is modelled " \
                "so far (DESIGN.md §7.4). The document itself is fine — but parsing it would " \
                "drop the fields that make it a #{type}, and re-serialising the result would " \
                "produce a different invoice under the same number."
        end

        # Delegated to {RoundingInference}: the strategy is not in the document, so it has
        # to be inferred from the summaries — which is reasoning about arithmetic rather
        # than reading elements, and belongs somewhere else.
        def resolve_rounding(invoice, fa_node)
          RoundingInference.apply(
            invoice, RoundingInference.stated_from(fa_node) { |node, name| text(node, name) }
          )
        end
      end
    end
  end
end
