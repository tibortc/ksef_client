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
    # **Two fields are optional for a buyer and mandatory for a seller**, both read from the
    # schema rather than assumed (docs/REFERENCE.md §8.2a):
    #
    # - `name` — `TPodmiot1` is a plain sequence of `NIP` and `Nazwa`; `TPodmiot2` puts `Nazwa`
    #   inside an `<xsd:sequence minOccurs="0">` after a four-way identification choice.
    # - `address` — `Podmiot1/Adres` is mandatory, while `Podmiot2/Adres` is `minOccurs="0"`,
    #   *"opcjonalne dla przypadków określonych w art. 106e ust. 5 pkt 3"* — the simplified
    #   invoice.
    #
    # Neither is theoretical: upstream's own corpus has a buyer identified by NIP alone, and
    # refusing an address-less buyer would reject valid FA(3) as if it were malformed.
    Subject = Data.define(:nip, :name, :address, :local_government_unit, :vat_group_member) do
      include Canonical

      def initialize(nip:, address: nil, name: nil, local_government_unit: false, vat_group_member: false)
        super
      end

      # @param role [Symbol] :seller or :buyer
      # @raise [Ksef::ValidationError] if a seller is missing a name or an address
      def to_fa3(role:)
        content = { "DaneIdentyfikacyjne" => identity_for(role) }
        if address.nil?
          raise ValidationError, "A seller (Podmiot1) must have an address" if role == :seller
        else
          content["Adres"] = address.to_fa3
        end
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
