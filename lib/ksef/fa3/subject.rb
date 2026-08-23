# frozen_string_literal: true

module Ksef
  module FA3
    # A party to the invoice — seller (`Podmiot1`) or buyer (`Podmiot2`).
    #
    # The two are not symmetric in the schema, which is why `#to_fa3` takes a role. The
    # buyer carries two mandatory flags the seller does not have (docs/REFERENCE.md §8.2):
    # `JST` and `GV`, stating whether the buyer is a subordinate local-government unit and
    # a VAT-group member. Both default to "no", because that is the answer for an ordinary
    # domestic sale and because omitting them makes the document schema-invalid — a caller
    # should not have to discover that from a rejection.
    # `name` is optional, and only for a buyer. `TPodmiot1` is a plain sequence of `NIP` and
    # `Nazwa`, both mandatory; `TPodmiot2` puts `Nazwa` inside an `<xsd:sequence
    # minOccurs="0">` following a four-way identification choice (docs/REFERENCE.md §8.2a).
    # Upstream's own test corpus has a buyer identified by NIP alone, so this is not a
    # theoretical branch — it is a document that must parse.
    Subject = Data.define(:nip, :name, :address, :local_government_unit, :vat_group_member) do
      def initialize(nip:, address:, name: nil, local_government_unit: false, vat_group_member: false)
        super
      end

      # @param role [Symbol] :seller or :buyer
      def to_fa3(role:)
        content = { "DaneIdentyfikacyjne" => identity_for(role), "Adres" => address.to_fa3 }
        return content unless role == :buyer

        content.merge(
          "JST" => Formatting.flag(local_government_unit),
          "GV" => Formatting.flag(vat_group_member)
        )
      end

      private

      def identity_for(role)
        if role == :seller && name.nil?
          raise ValidationError, "A seller (Podmiot1) must have a name; only a buyer may omit it"
        end

        identity = { "NIP" => NIP.validate!(nip, field: "#{role} NIP") }
        # Omitted rather than written empty when absent: `<Nazwa/>` fails TZnakowy512's
        # minimum length, so an empty element would turn a legal buyer into an invalid one.
        identity["Nazwa"] = name unless name.nil?
        identity
      end
    end
  end
end
