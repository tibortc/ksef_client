# frozen_string_literal: true

module Ksef
  module FA3
    # A party to the invoice — seller (`Podmiot1`) or buyer (`Podmiot2`), and on a correction
    # the same two as the *corrected* invoice stated them (`Podmiot1K`, `Podmiot2K`).
    #
    # The roles are not symmetric in the schema, which is why `#to_fa3` takes one. The
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
    #
    # The two `K` roles mirror those, minus what makes no sense on a snapshot of the past:
    # neither carries `JST`/`GV`, and `Podmiot1K/Adres` is mandatory as `Podmiot1/Adres` is.
    # See {Correction} and docs/REFERENCE.md §8.4.
    Subject = Data.define(:nip, :name, :address, :local_government_unit, :vat_group_member, :buyer_id)

    # Roles, defaults and serialisation for {Ksef::FA3::Subject}. Reopened rather than using a
    # `Data.define` block so the constants land on the class.
    class Subject
      include Canonical

      # The element each role writes into. Also the role whitelist: a role not named here is
      # refused rather than silently treated as a buyer.
      ELEMENTS = {
        seller: "Podmiot1", buyer: "Podmiot2",
        previous_seller: "Podmiot1K", previous_buyer: "Podmiot2K"
      }.freeze

      # `Podmiot1` and `Podmiot1K` both make `Nazwa` and `Adres` mandatory; the two buyer
      # roles make both optional.
      NAMED_PARTIES = %i[seller previous_seller].freeze

      def initialize(nip:, address: nil, name: nil, local_government_unit: false,
                     vat_group_member: false, buyer_id: nil)
        super
      end

      # @param role [Symbol] `:seller`, `:buyer`, `:previous_seller` or `:previous_buyer`
      # @raise [Ksef::ValidationError] if a seller is missing a name or an address, or the
      #   role is not one of the four
      def to_fa3(role:)
        element = element_for(role)
        content = { "DaneIdentyfikacyjne" => identity_for(role, element) }
        if address.nil?
          raise ValidationError, "A #{role} (#{element}) must have an address" if NAMED_PARTIES.include?(role)
        else
          content["Adres"] = address.to_fa3
        end

        content.merge(buyer_fields(role)).compact
      end

      private

      def element_for(role)
        ELEMENTS.fetch(role) do
          raise ValidationError,
                "Unknown subject role #{role.inspect}. Permitted: #{ELEMENTS.keys.map(&:inspect).join(", ")}"
        end
      end

      # `IDNabywcy` is *"unikalny klucz powiązania danych nabywcy na fakturach
      # korygujących"* — the key tying a `Podmiot2K` to the `Podmiot2` it corrects. Both
      # sides carry it, and a correction naming more than one buyer has nothing else to pair
      # them by, so it is a field of the model rather than an element to lose.
      #
      # `JST`/`GV` are the buyer's alone: `Podmiot2K` has no such elements, and emitting them
      # there would fail {Serializer}'s key check rather than merely being ignored.
      def buyer_fields(role)
        case role
        when :buyer
          { "IDNabywcy" => buyer_id,
            "JST" => Formatting.flag(local_government_unit),
            "GV" => Formatting.flag(vat_group_member) }
        when :previous_buyer then { "IDNabywcy" => buyer_id }
        else {}
        end
      end

      def identity_for(role, element)
        if NAMED_PARTIES.include?(role) && name.nil?
          raise ValidationError, "A #{role} (#{element}) must have a name; only a buyer may omit it"
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
