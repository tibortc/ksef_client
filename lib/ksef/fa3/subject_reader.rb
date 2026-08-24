# frozen_string_literal: true

module Ksef
  module FA3
    # Reads a party element — `Podmiot1`, `Podmiot2`, `Podmiot1K`, `Podmiot2K` — into a
    # {Subject}.
    #
    # Split out of {Parser} because all four roles share it and none of the reasoning is
    # about invoices: it is about which elements each `Podmiot` type makes mandatory, and
    # about the one construct the model cannot carry.
    module SubjectReader
      class << self
        # Namespace-aware element reading; see {NodeReader}.
        include NodeReader

        # `role` decides which of `Nazwa` and `Adres` are required: `TPodmiot1` makes both
        # mandatory, `TPodmiot2` makes both optional — the address explicitly *"opcjonalne dla
        # przypadków określonych w art. 106e ust. 5 pkt 3"*, the simplified invoice
        # (docs/REFERENCE.md §8.2a). Requiring them of a buyer rejected valid FA(3).
        # `Podmiot1K` and `Podmiot2K` follow their live counterparts (§8.4).
        #
        # @param node [Nokogiri::XML::Node] the party element
        # @param role [Symbol] one of {Subject::ELEMENTS}' keys
        # @return [Subject]
        def subject_from(node, role:)
          identity = require_element(node, "DaneIdentyfikacyjne", context: node.name)
          named = Subject::NAMED_PARTIES.include?(role)

          Subject.new(
            nip: identity_nip(identity),
            name: named ? text!(identity, "Nazwa") : text(identity, "Nazwa"),
            address: address_from(node, role: role),
            # Absent means "no" — which is both the schema's meaning for the seller, where
            # neither element exists, and the right default for a buyer that omits them.
            local_government_unit: Formatting.unflag(text(node, "JST")),
            vat_group_member: Formatting.unflag(text(node, "GV")),
            buyer_id: text(node, "IDNabywcy")
          )
        end

        private

        def address_from(node, role:)
          address = element(node, "Adres")
          if address.nil?
            if Subject::NAMED_PARTIES.include?(role)
              raise ValidationError, "#{node.name} is missing the mandatory <Adres> element"
            end

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

          alternatives = identity.element_children.map(&:name).reject { |name| name == "Nazwa" }
          raise ValidationError,
                "#{identity.parent.name} is identified by #{alternatives.join(", ")} rather than NIP. " \
                "This model carries a NIP only (DESIGN.md §7.4); the document itself is fine."
        end
      end
    end
  end
end
