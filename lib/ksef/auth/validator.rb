# frozen_string_literal: true

require "nokogiri"

module Ksef
  module Auth
    # XSD validation for `AuthTokenRequest`, mirroring {Ksef::FA3::Validator}.
    #
    # Both pinned schema files are structurally identical — diffing them shows the only
    # differences are the target namespace and the three IP patterns, which v2.0 got wrong
    # badly enough that libxml2 will not compile the file at all (docs/REFERENCE.md §14.4).
    #
    # So **v2.1's file is the single source of validation rules**, and its target namespace
    # is rewritten in memory to match the document being checked. Exactly the approach
    # {Ksef::FA3::Validator} takes to its remote `schemaLocation`, and for the same reason:
    # the pinned files stay byte-identical, so their recorded digests keep verifying.
    #
    # The upshot is that a 2.0 document — which is what the API expects and what both
    # official clients emit — gets validated against rules that actually compile, which is
    # strictly better than validating it against v2.0 itself. That is impossible.
    module Validator
      SCHEMA_DIR = File.expand_path("schema", __dir__)
      SOURCE = File.join(SCHEMA_DIR, "schemat_auth_v2-1.xsd")
      SOURCE_NAMESPACE = NAMESPACES.fetch("2.1")

      class << self
        # @param namespace [String] one of {Ksef::Auth::NAMESPACES}' values
        # @return [Nokogiri::XML::Schema] memoised per namespace; compiling is not free and
        #   a client authenticating repeatedly should pay once
        def schema_for(namespace)
          reject_unknown_namespace(namespace)
          schemas[namespace] ||= Nokogiri::XML::Schema(retargeted_source(namespace))
        end

        # @param xml [String, Nokogiri::XML::Document]
        # @return [Array<String>] validation messages, empty when the document is valid
        def errors_for(xml)
          document = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml)
          schema_for(namespace_of(document)).validate(document).map(&:message)
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
          raise ValidationError, "AuthTokenRequest is not schema-valid:\n#{detail}#{advisory}"
        end

        private

        def schemas = @schemas ||= {}

        # Read from the document rather than assumed, so a request built for either version
        # validates against the matching rules — but only the two known namespaces are
        # accepted, otherwise a typo would silently validate against itself.
        def namespace_of(document)
          document.root&.namespace&.href
        end

        def reject_unknown_namespace(namespace)
          return if NAMESPACES.value?(namespace)

          raise ValidationError,
                "AuthTokenRequest declares namespace #{namespace.inspect}, which is not a known " \
                "schema version. Expected one of #{NAMESPACES.values.map(&:inspect).join(", ")}."
        end

        def retargeted_source(namespace)
          source = File.read(SOURCE, encoding: "UTF-8")
          return source if namespace == SOURCE_NAMESPACE

          source.gsub(SOURCE_NAMESPACE, namespace)
        end
      end
    end
  end
end
