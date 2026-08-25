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

      # `is_a?`, not a `respond_to?` pair. Checking two of the methods and then calling five
      # more meant an object answering only those two made `errors_for` raise `NoMethodError`
      # — the very symptom this guard exists to prevent. The message promises a class.
      def subject_errors(subject, field, role:)
        return [Issue.new(field: field, message: "is required")] if subject.nil?
        return [Issue.new(field: field, message: "is not a Ksef::FA3::Subject")] unless subject.is_a?(Subject)

        [
          *nip_errors(subject.nip, "#{field}.nip"),
          *name_errors(subject.name, "#{field}.name", role: role),
          *address_errors(subject.address, "#{field}.address", role: role),
          *flag_errors(subject, field, role: role),
          *buyer_id_errors(subject, field, role: role)
        ]
      end

      # **A field the chosen role cannot carry is silently dropped by {Subject#to_fa3}**, so
      # tier 1 names it. `JST`/`GV` exist only on `Podmiot2`; `IDNabywcy` only on `Podmiot2`
      # and `Podmiot2K`. Everywhere else the serializer simply does not write them, which in a
      # codebase that otherwise raises on anything it cannot represent is the wrong kind of
      # quiet — a caller who set `local_government_unit: true` on a `Podmiot1K` meant it.
      #
      # Only a *set* flag is reported. Both default to false, and false is also "not
      # applicable", so a defaulted flag on a seller says nothing and must not be complained
      # about. The values themselves are canonicalised by {Subject#initialize}, which is why
      # this no longer checks them: an unreadable flag cannot reach a constructed object.
      def flag_errors(subject, field, role:)
        return [] if role == :buyer

        { "local_government_unit" => subject.local_government_unit,
          "vat_group_member" => subject.vat_group_member }.filter_map do |name, value|
          next unless value

          Issue.new(field: "#{field}.#{name}",
                    message: "is set on a #{role}, whose element carries no JST/GV; " \
                             "only Podmiot2 does, so it would be dropped silently")
        end
      end

      # `IDNabywcy` is written by both buyer roles and by neither seller role.
      def buyer_id_errors(subject, field, role:)
        unless Subject::NAMED_PARTIES.include?(role)
          return text_errors(subject.buyer_id, "#{field}.buyer_id", BUYER_ID_TEXT)
        end
        return [] if subject.buyer_id.nil?

        [Issue.new(field: "#{field}.buyer_id",
                   message: "is set on a #{role}, whose element carries no IDNabywcy; " \
                            "only Podmiot2 and Podmiot2K do, so it would be dropped silently")]
      end

      # Checked here as well as in {Subject#to_fa3} on purpose. Serialisation raises, which
      # is the right last defence but a poor first one: it reports the first bad NIP and
      # hides the second.
      #
      # Note this is **stricter than TEST**, deliberately: KSeF validates NIP checksums in
      # production only (docs/REFERENCE.md §15.3), so a green TEST run proves nothing here
      # and relaxing the check would move the failure to the worst possible moment.
      # The encoding check comes first for the reason {FieldChecks} gives: `NIP.normalize`
      # calls `strip` and `gsub`, both of which raise `Encoding::CompatibilityError` on text
      # tagged UTF-8 that is not — outside this gem's hierarchy, and so outside
      # {Invoice#errors}' rescue. A mojibake NIP out of an ERP is exactly the case §15.1 calls
      # the likely one.
      def nip_errors(nip, field)
        bad_encoding = encoding_issue(nip, field)
        return [bad_encoding] if bad_encoding

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
        # `is_a?`, for the reason {#subject_errors} gives: checking `respond_to?(:line1)` and
        # then reading `line2` and `country` made `#errors` raise `NoMethodError` on an object
        # that answered only the first — the symptom the guard exists to prevent.
        return [Issue.new(field: field, message: "is not a Ksef::FA3::Address")] unless address.is_a?(Address)

        [
          *text_errors(address.line1, "#{field}.line1", LONG_TEXT, required: true),
          *text_errors(address.line2, "#{field}.line2", LONG_TEXT),
          enum_issue("#{field}.country", "TKodKraju", address.country)
        ].compact
      end
    end
  end
end
