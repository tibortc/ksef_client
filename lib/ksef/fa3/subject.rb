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
    Subject = Data.define(:nip, :name, :address, :local_government_unit, :vat_group_member) do
      def initialize(nip:, name:, address:, local_government_unit: false, vat_group_member: false)
        super
      end

      # @param role [Symbol] :seller or :buyer
      def to_fa3(role:)
        content = {
          "DaneIdentyfikacyjne" => { "NIP" => NIP.validate!(nip, field: "#{role} NIP"), "Nazwa" => name },
          "Adres" => address.to_fa3
        }

        if role == :buyer
          content["JST"] = Formatting.flag(local_government_unit)
          content["GV"] = Formatting.flag(vat_group_member)
        end

        content
      end
    end
  end
end
