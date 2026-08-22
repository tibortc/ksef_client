# frozen_string_literal: true

require "nokogiri"

module Ksef
  module Auth
    # XSD validation for `AuthTokenRequest`, mirroring {Ksef::FA3::Validator}.
    #
    # Simpler than its FA(3) counterpart in one respect and messier in another. Simpler
    # because the auth schema is self-contained — no `xsd:import`, so nothing needs
    # redirecting to avoid a network fetch. Messier because **only v2.1 is usable**: v2.0's
    # IP patterns contain `\b`, which XSD regex has no concept of, so libxml2 fails to
    # compile the entire file rather than just those facets (docs/REFERENCE.md §14.4). v2.0
    # stays pinned for the record; nothing loads it.
    module Validator
      SCHEMA_DIR = File.expand_path("schema", __dir__)
      SCHEMA = File.join(SCHEMA_DIR, "schemat_auth_v2-1.xsd")

      class << self
        # Compiled once and memoised — a client authenticating repeatedly should not
        # recompile the schema each time.
        #
        # @return [Nokogiri::XML::Schema]
        def schema
          @schema ||= Nokogiri::XML::Schema(File.read(SCHEMA, encoding: "UTF-8"))
        end

        # @param xml [String, Nokogiri::XML::Document]
        # @return [Array<String>] validation messages, empty when the document is valid
        def errors_for(xml)
          document = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml)
          schema.validate(document).map(&:message)
        end

        # @return [Boolean]
        def valid?(xml) = errors_for(xml).empty?

        # @param advisory [String] appended to the message; used to explain that a failure
        #   may stem from an upstream schema defect rather than the caller's data
        # @raise [Ksef::ValidationError] listing every schema violation
        def validate!(xml, advisory: "")
          errors = errors_for(xml)
          return true if errors.empty?

          detail = errors.map { |e| "  - #{e}" }.join("\n")
          raise ValidationError, "AuthTokenRequest does not conform to schema v2.1:\n#{detail}#{advisory}"
        end
      end
    end
  end
end
