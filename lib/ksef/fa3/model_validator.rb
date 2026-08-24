# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1a — checks on the invoice **object**, before it becomes a document
    # (DESIGN.md §7.7, as amended 2026-08-24).
    #
    # Fast, field-addressed, and needing no XML: required fields, enum membership, NIP
    # checksums, string lengths, date sanity. The point is not to duplicate the schema — tier
    # 2 does that better — but to say *which value* is wrong in terms the caller recognises,
    # before they have to read a libxml2 message about a facet.
    #
    # ## It also has a contract tier 2 cannot give
    #
    # **If this passes, `#to_xml` will not raise.** Serialisation refuses several things
    # outright — a NIP that fails its checksum, a seller with no name or address, a line whose
    # net can be neither read nor derived, a rate code with no summary bucket — and each
    # arrives as an exception rather than a message. Checking them here turns every one into a
    # collected, addressed error, which is why {Invoice#errors} runs this first and stops if
    # anything comes back.
    #
    # ## What it deliberately does not check
    #
    # **Arithmetic.** Whether the summaries reconcile with the lines is tier 3
    # (docs/REFERENCE.md §15.6), and it is not built.
    #
    # **Anything global.** Duplicate detection (§15.2) is a property of KSeF's ten-year
    # history, not of this document.
    #
    # **Sign.** `TKwotowy` permits negative amounts and corrections need them, so a negative
    # net is not an error here.
    module ModelValidator
      # `TZnakowy` and `TZnakowy512`: both `minLength="1"`, differing only in the ceiling. A
      # value that is present but empty is a schema violation, not an absent value.
      SHORT_TEXT = 256
      LONG_TEXT = 512

      # `Adnotacje` is an anonymous complex type, so the generated metadata keys it by path
      # rather than by name — the same key {Serializer} resolves when it rejects an unknown
      # element there.
      ANNOTATIONS_TYPE = "Faktura/Fa/Adnotacje"

      # §15.4: `P_1` must not be later than the date KSeF accepts the document — a date in
      # *KSeF's* timezone, which is unknowable here. Comparing against a local `Date.today`
      # would reject perfectly good invoices around midnight for any caller west of Warsaw, so
      # this allows a day of slack and flags only a date that is unambiguously in the future.
      # The same-day boundary is left to the service, which is the only party that can decide
      # it.
      FUTURE_TOLERANCE_DAYS = 1

      class << self
        # Value-level checks: encoding, xsd:token collapse, lengths, enum membership.
        include FieldChecks

        # @param invoice [Invoice]
        # @return [Array<Issue>] empty when the model is sound
        def errors_for(invoice)
          [
            *subject_errors(invoice.seller, "seller", role: :seller),
            *subject_errors(invoice.buyer, "buyer", role: :buyer),
            *header_errors(invoice),
            *annotation_errors(invoice.annotations),
            *invoice.lines.each_with_index.flat_map { |line, index| line_errors(line, index) }
          ]
        end

        private

        def header_errors(invoice)
          issues = []
          issues.concat(text_errors(invoice.number, "number", SHORT_TEXT, required: true))
          issues << enum_issue("currency", "TKodWaluty", invoice.currency)
          issues << enum_issue("invoice_type", "TRodzajFaktury", invoice.invoice_type)
          issues << future_date_issue(invoice.issue_date)
          issues.compact
        end

        def subject_errors(subject, field, role:)
          return [Issue.new(field: field, message: "is required")] if subject.nil?
          unless subject.respond_to?(:nip) && subject.respond_to?(:address)
            return [Issue.new(field: field, message: "is not a Ksef::FA3::Subject")]
          end

          [
            *nip_errors(subject.nip, "#{field}.nip"),
            *name_errors(subject.name, "#{field}.name", role: role),
            *address_errors(subject.address, "#{field}.address", role: role),
            *flag_errors(subject, field, role: role)
          ]
        end

        # `JST` and `GV` are written through {Formatting.flag}, which raises on anything that is
        # not boolean-ish. Only a buyer carries them, so only a buyer is checked.
        def flag_errors(subject, field, role:)
          return [] unless role == :buyer

          { "local_government_unit" => subject.local_government_unit,
            "vat_group_member" => subject.vat_group_member }.filter_map do |name, value|
            next if [true, false, nil, "1", "2", 1, 2].include?(value)

            Issue.new(field: "#{field}.#{name}", message: "#{value.inspect} is not a yes/no value")
          end
        end

        # `annotations` is a public constructor field the model tier used to ignore entirely, so
        # an unknown key passed the model and then made the serializer raise — the one hole in
        # this module's contract that a 2026-08-24 review could still find. Names are checked
        # against the generated schema metadata, one level deep, which is as far as the
        # serializer's own key check reaches per element.
        def annotation_errors(annotations)
          return [Issue.new(field: "annotations", message: "must be a Hash")] unless annotations.is_a?(Hash)

          permitted = Generated::Types.ordered_elements(ANNOTATIONS_TYPE).map { |particle| particle[:name] }
          # An empty list means the generated metadata no longer keys this type by the path
          # above — a codegen change, not a caller's mistake, and no reason to reject their
          # annotations.
          return [] if permitted.empty?

          (annotations.keys.map(&:to_s) - permitted).map do |unknown|
            Issue.new(field: "annotations", message: "#{unknown.inspect} is not an element of Adnotacje")
          end
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

        # `TPodmiot1` requires `Nazwa`; `TPodmiot2` leaves it optional (§8.2a).
        def name_errors(name, field, role:)
          return [Issue.new(field: field, message: "is required for a seller")] if name.nil? && role == :seller

          text_errors(name, field, LONG_TEXT)
        end

        # `Podmiot1/Adres` is mandatory, `Podmiot2/Adres` is not (§8.2a).
        def address_errors(address, field, role:)
          if address.nil?
            return role == :seller ? [Issue.new(field: field, message: "is required for a seller")] : []
          end
          return [Issue.new(field: field, message: "is not a Ksef::FA3::Address")] unless address.respond_to?(:line1)

          [
            *text_errors(address.line1, "#{field}.line1", LONG_TEXT, required: true),
            *text_errors(address.line2, "#{field}.line2", LONG_TEXT),
            enum_issue("#{field}.country", "TKodKraju", address.country)
          ].compact
        end

        def line_errors(line, index)
          field = "lines[#{index}]"
          return [Issue.new(field: field, message: "is not a Ksef::FA3::Line")] unless line.respond_to?(:vat_rate)

          [
            *text_errors(line.name, "#{field}.name", LONG_TEXT),
            *text_errors(line.unit, "#{field}.unit", SHORT_TEXT),
            enum_issue("#{field}.vat_rate", "TStawkaPodatku", line.vat_rate),
            net_issue(line, field)
          ].compact
        end

        # {Line#net} raises when it can neither read a net nor derive one; the same condition,
        # reported rather than thrown.
        def net_issue(line, field)
          return nil unless line.net_amount.nil? && (line.quantity.nil? || line.net_unit_price.nil?)

          Issue.new(field: field,
                    message: "needs either net_amount, or both quantity and net_unit_price")
        end

        def future_date_issue(issue_date)
          latest = Date.today + FUTURE_TOLERANCE_DAYS
          return nil unless issue_date > latest

          Issue.new(field: "issue_date",
                    message: "#{issue_date} is in the future; KSeF rejects an issue date later " \
                             "than the date it accepts the document (docs/REFERENCE.md §15.4)")
        end
      end
    end
  end
end
