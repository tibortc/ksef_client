# frozen_string_literal: true

require "nokogiri"

module Ksef
  module FA3
    # XSD validation against the bundled FA(3) schema (DESIGN.md §7.7 tier 2).
    #
    # The schema cannot be compiled as it ships. Its single `xsd:import` points at an
    # absolute `http://crd.gov.pl/…` URL, so libxml2 would try to fetch it over the network
    # at validation time — unacceptable for an offline, deterministic test suite, and a
    # silent hang or failure in an air-gapped deployment.
    #
    # So the import is redirected to the bundled copy **in memory**. The pinned file on
    # disk stays byte-for-byte identical, which is what keeps its recorded digest
    # verifying (docs/REFERENCE.md §1).
    module Validator
      SCHEMA_DIR = File.expand_path("schema", __dir__)
      MAIN_SCHEMA = File.join(SCHEMA_DIR, "schemat_FA(3)_v1-0E.xsd")
      BASE_SCHEMA_DIR = File.join(SCHEMA_DIR, "bazowe")

      class << self
        # Compiled once and memoised: compiling the FA(3) schema is expensive, and a
        # single client validating many invoices should pay for it once.
        #
        # @return [Nokogiri::XML::Schema]
        def schema
          @schema ||= Nokogiri::XML::Schema.from_document(rewritten_schema_document)
        end

        # @param xml [String, Nokogiri::XML::Document]
        # @return [Array<String>] validation messages, empty when the document is valid
        #
        # **Well-formedness is checked first, and separately.** Nokogiri parses in recovery
        # mode by default, so a document with an unclosed root or trailing text after it comes
        # back as a usable tree — and that recovered tree validates clean against the schema.
        # Until 2026-08-24 this method never looked at `document.errors`, so `valid?` returned
        # true for XML that is not XML. KSeF's first admission rule is "a correct XML 1.0
        # document" (docs/REFERENCE.md §15.1), and it is the rule most likely to be violated by
        # a broken template or a truncated upload.
        def errors_for(xml)
          document = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml)
          malformed = document.errors.map { |error| "not well-formed XML: #{error.message.strip}" }
          return malformed unless malformed.empty?

          schema.validate(document).map(&:message)
        end

        # @return [Boolean]
        def valid?(xml) = errors_for(xml).empty?

        # @raise [Ksef::ValidationError] listing every schema violation
        def validate!(xml)
          errors = errors_for(xml)
          return true if errors.empty?

          detail = errors.map { |e| "  - #{e}" }.join("\n")
          raise ValidationError, "Invoice does not conform to the FA(3) schema:\n#{detail}"
        end

        private

        def rewritten_schema_document
          document = Nokogiri::XML(File.read(MAIN_SCHEMA, encoding: "UTF-8"))

          document.xpath("//*[local-name()='import']").each do |import|
            location = import["schemaLocation"]
            next unless location&.start_with?("http")

            # An absolute local path, so resolution needs no base-URI handling.
            import["schemaLocation"] = File.join(BASE_SCHEMA_DIR, File.basename(location))
          end

          document
        end
      end
    end
  end
end
