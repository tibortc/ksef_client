# frozen_string_literal: true

require "nokogiri"

module Ksef
  module UPO
    # Offline XSD validation for a received UPO (docs/REFERENCE.md §12, §14.3).
    #
    # Simpler than {Ksef::FA3::Validator} and {Ksef::Auth::Validator} in one respect: the
    # pinned `upo-v4-3.xsd` imports nothing and declares no remote `schemaLocation`, so it
    # compiles offline as shipped with no in-memory rewriting.
    #
    # ## This is a diagnostic. It is never a gate.
    #
    # There is deliberately **no `validate!`** here, unlike the other two validators, and the
    # omission is the design. A UPO is the legal proof that an invoice was received; whether
    # it satisfies a schema is interesting, but it is never a reason to discard the bytes or
    # to fail an operation that has already succeeded at the far end. Offering a raising
    # method would make gating the path of least resistance. A caller who genuinely wants to
    # raise can write `raise unless result.valid?` and own that decision explicitly.
    #
    # ## Why the receiving-party mismatch is a warning
    #
    # Measured on the pinned artifacts: all six of upstream's worked examples fail upstream's
    # own schema, each with exactly one error, and always the same one — the schema fixes
    # {UPO::RECEIVING_PARTY_ELEMENT} to `"Ministerstwo Finansów"` while the examples, all
    # captured on TEST, carry `"Ministerstwo Finansów - środowisko testowe (TE)"`.
    #
    # §14.3 permits either relaxing the constraint or reporting the mismatch as a warning.
    # This takes the second, because it keeps strictly more information: in production the
    # `fixed` value is presumably correct, so a mismatch there would be a genuine anomaly —
    # and relaxing the schema would mean never hearing about it. The observed value is read
    # from the document rather than scraped out of the error message, so it is reliable.
    module Validator
      SOURCE = File.expand_path("schema/upo-v4-3.xsd", __dir__)

      # libxml2's wording for a `fixed` violation. Matched on the element name as well, so
      # a fixed-value complaint about any *other* element stays an error.
      FIXED_VALUE_COMPLAINT = /#{Regexp.escape(RECEIVING_PARTY_ELEMENT)}.*fixed value constraint/m

      class << self
        # @return [Nokogiri::XML::Schema] memoised; compiling is not free and a client
        #   archiving many UPOs should pay once
        def schema = @schema ||= Nokogiri::XML::Schema(File.read(SOURCE, encoding: "UTF-8"))

        # @param xml [String, Nokogiri::XML::Document, Document]
        # @return [Validation]
        def validate(xml)
          document = parse(xml)
          messages = schema.validate(document).map(&:message)
          expected, real = messages.partition { |message| FIXED_VALUE_COMPLAINT.match?(message) }

          Validation.new(
            errors: real.freeze,
            warnings: expected.freeze,
            receiving_party: receiving_party(document)
          )
        end

        # @return [Boolean] true when the document has no violation beyond the known
        #   upstream environment-marker defect
        def valid?(xml) = validate(xml).valid?

        # The receiving party as the document actually states it — which doubles as a way to
        # tell which environment issued a UPO, since only production is expected to carry the
        # bare `"Ministerstwo Finansów"`.
        #
        # @return [String, nil]
        def receiving_party(xml)
          document = parse(xml)
          document.at_xpath("//upo:#{RECEIVING_PARTY_ELEMENT}", "upo" => NAMESPACE)&.text
        end

        private

        def parse(xml)
          return xml if xml.is_a?(Nokogiri::XML::Document)

          Nokogiri::XML(xml.respond_to?(:xml) ? xml.xml : xml.to_s)
        end
      end
    end
  end
end
