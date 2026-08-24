# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a's checks on a party — `Podmiot1`, `Podmiot2`, and on a correction the two `K`
    # variants of them.
    #
    # Split out of {ModelValidator} because all four roles share it and the asymmetries
    # between them are a subject of their own (docs/REFERENCE.md §8.2a, §8.4): which of
    # `Nazwa` and `Adres` are mandatory, which roles carry `JST`/`GV`, and which carry the
    # `IDNabywcy` linking key. {ModelValidator} decides *which* parties an invoice has.
    #
    # Mixed into {ModelValidator}.
    module SubjectChecks
      # Included rather than assumed present. Constant lookup is **lexical**, so `LONG_TEXT`
      # here resolves through this module's own ancestors and not through whatever
      # {ModelValidator} happens to have mixed in.
      include FieldChecks

      private

      def subject_errors(subject, field, role:)
        return [Issue.new(field: field, message: "is required")] if subject.nil?
        unless subject.respond_to?(:nip) && subject.respond_to?(:address)
          return [Issue.new(field: field, message: "is not a Ksef::FA3::Subject")]
        end

        [
          *nip_errors(subject.nip, "#{field}.nip"),
          *name_errors(subject.name, "#{field}.name", role: role),
          *address_errors(subject.address, "#{field}.address", role: role),
          *flag_errors(subject, field, role: role),
          *buyer_id_errors(subject, field, role: role)
        ]
      end

      # `JST` and `GV` are written through {Formatting.flag}, which raises on anything that is
      # not boolean-ish. Only a buyer carries them — `Podmiot2K` has no such elements — so
      # only a buyer is checked.
      def flag_errors(subject, field, role:)
        return [] unless role == :buyer

        { "local_government_unit" => subject.local_government_unit,
          "vat_group_member" => subject.vat_group_member }.filter_map do |name, value|
          next if [true, false, nil, "1", "2", 1, 2].include?(value)

          Issue.new(field: "#{field}.#{name}", message: "#{value.inspect} is not a yes/no value")
        end
      end

      # `IDNabywcy` is written by both buyer roles and by neither seller role.
      def buyer_id_errors(subject, field, role:)
        return [] if Subject::NAMED_PARTIES.include?(role)

        text_errors(subject.buyer_id, "#{field}.buyer_id", BUYER_ID_TEXT)
      end

      # Checked here as well as in {Subject#to_fa3} on purpose. Serialisation raises, which
      # is the right last defence but a poor first one: it reports the first bad NIP and
      # hides the second.
      #
      # Note this is **stricter than TEST**, deliberately: KSeF validates NIP checksums in
      # production only (docs/REFERENCE.md §15.3), so a green TEST run proves nothing here
      # and relaxing the check would move the failure to the worst possible moment.
      def nip_errors(nip, field)
        NIP.validate!(nip, field: field)
        []
      rescue ValidationError => e
        [Issue.new(field: field, message: e.message.sub("#{field} ", ""))]
      end

      # `TPodmiot1` requires `Nazwa`; `TPodmiot2` leaves it optional (§8.2a). `Podmiot1K`
      # and `Podmiot2K` follow their live counterparts (§8.4).
      def name_errors(name, field, role:)
        if name.nil? && Subject::NAMED_PARTIES.include?(role)
          return [Issue.new(field: field, message: "is required for a #{role}")]
        end

        text_errors(name, field, LONG_TEXT)
      end

      # `Podmiot1/Adres` and `Podmiot1K/Adres` are mandatory; the two buyer roles are not
      # (§8.2a, §8.4).
      def address_errors(address, field, role:)
        if address.nil?
          return [] unless Subject::NAMED_PARTIES.include?(role)

          return [Issue.new(field: field, message: "is required for a #{role}")]
        end
        return [Issue.new(field: field, message: "is not a Ksef::FA3::Address")] unless address.respond_to?(:line1)

        [
          *text_errors(address.line1, "#{field}.line1", LONG_TEXT, required: true),
          *text_errors(address.line2, "#{field}.line2", LONG_TEXT),
          enum_issue("#{field}.country", "TKodKraju", address.country)
        ].compact
      end
    end
  end
end
