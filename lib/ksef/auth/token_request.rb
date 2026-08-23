# frozen_string_literal: true

require "nokogiri"

module Ksef
  module Auth
    # The `AuthTokenRequest` document — step 2 of the authentication flow
    # (docs/REFERENCE.md §4.2). Built here, then XAdES-signed and submitted to
    # `POST /auth/xades-signature`. {#document} exposes the mutable tree because an
    # enveloped signature has to be inserted *into* the document — {Signer} cannot assemble
    # a signed request from a string afterwards.
    #
    # Defaults to the **2.0** namespace, matching both official clients and every upstream
    # example; `schema_version:` selects 2.1. See {Ksef::Auth::NAMESPACES} for why, and
    # §14.4 for why validation nonetheless uses v2.1's rules.
    class TokenRequest
      ROOT = "AuthTokenRequest"

      SUBJECT_IDENTIFIER_TYPES = %w[certificateSubject certificateFingerprint].freeze

      # A choice of four, in schema order. The last two cannot hold their real-world values
      # because of an upstream regex defect (§14.4); they are still offered, because the
      # server looks up the actual identifier and emitting the absurd value the facet wants
      # would be worse than failing a local check.
      CONTEXT_TYPES = %i[nip internal_id nip_vat_ue peppol_id].freeze

      CONTEXT_ELEMENTS = {
        nip: "Nip", internal_id: "InternalId", nip_vat_ue: "NipVatUe", peppol_id: "PeppolId"
      }.freeze

      # Context types whose schema pattern is intact, and for which `#validate!` is
      # therefore meaningful rather than advisory.
      VALIDATABLE_CONTEXT_TYPES = %i[nip internal_id].freeze

      attr_reader :challenge, :context_type, :context_value, :subject_identifier_type, :allowed_ips,
                  :namespace, :schema_version

      # @param challenge [String] verbatim from `POST /auth/challenge`
      # @param context_type [Symbol] one of {CONTEXT_TYPES}
      # @param context_value [String] the identifier itself
      # @param subject_identifier_type [String] `"certificateSubject"` or
      #   `"certificateFingerprint"` — how KSeF should read the signer's identity out of
      #   the signing certificate (§4.4)
      # @param allowed_ips [Hash, AuthorizationPolicy, nil] optional client-IP whitelist,
      #   with any of `:addresses`, `:ranges`, `:masks`
      # @param schema_version [String] `"2.0"` (default) or `"2.1"`
      def initialize(challenge:, context_type:, context_value:,
                     subject_identifier_type: "certificateSubject", allowed_ips: nil,
                     schema_version: DEFAULT_SCHEMA_VERSION)
        @namespace = NAMESPACES.fetch(schema_version) do
          raise ValidationError,
                "Unknown schema version #{schema_version.inspect}. " \
                "Expected one of #{NAMESPACES.keys.map(&:inspect).join(", ")}."
        end
        @schema_version = schema_version
        @challenge = Challenge.validate_format!(challenge)
        @context_type = validate_context_type(context_type)
        @context_value = context_value
        @subject_identifier_type = validate_subject_identifier_type(subject_identifier_type)
        @allowed_ips = AuthorizationPolicy.coerce(allowed_ips)
        freeze
      end

      def to_xml
        document.to_xml(indent: 2, encoding: "UTF-8")
      end

      # @return [Nokogiri::XML::Document] the unsigned document, for {Signer} to sign in
      #   place — an enveloped signature has to be added to the tree, not to a string
      def document
        Nokogiri::XML::Document.new.tap do |doc|
          doc.encoding = "UTF-8"
          root = doc.create_element(ROOT)
          root.default_namespace = namespace
          doc.root = root

          add_text(doc, root, "Challenge", challenge)
          root.add_child(context_element(doc))
          add_text(doc, root, "SubjectIdentifierType", subject_identifier_type)
          root.add_child(policy_element(doc)) if allowed_ips
        end
      end

      # @raise [Ksef::ValidationError] if the document does not conform to schema v2.1
      def validate! = Validator.validate!(to_xml, advisory: advisory)

      def valid? = Validator.valid?(to_xml)

      # True when `#validate!` is a real check rather than one the upstream schema cannot
      # express (§14.4).
      def validatable? = VALIDATABLE_CONTEXT_TYPES.include?(context_type)

      private

      # Points at the ledger rather than restating the diagnosis, but says enough that the
      # failure is not mistaken for a bug in the caller's own data.
      def advisory
        return "" if validatable?

        "\nNote: the pinned schema's pattern for #{CONTEXT_ELEMENTS[context_type]} is defective upstream " \
          "(docs/REFERENCE.md §14.4), so this failure may not reflect your input."
      end

      def context_element(doc)
        doc.create_element("ContextIdentifier").tap do |node|
          add_text(doc, node, CONTEXT_ELEMENTS.fetch(context_type), context_value)
        end
      end

      def policy_element(doc)
        doc.create_element("AuthorizationPolicy").tap do |policy|
          allowed = doc.create_element("AllowedIps")
          # AllowedIps is mandatory inside the policy, so it is always created; the policy
          # itself guarantees at least one entry and yields them in schema order.
          allowed_ips.entries.each { |name, value| add_text(doc, allowed, name, value) }
          policy.add_child(allowed)
        end
      end

      def add_text(doc, parent, name, value)
        element = doc.create_element(name)
        element.content = value.to_s
        parent.add_child(element)
      end

      def validate_context_type(value)
        return value if CONTEXT_TYPES.include?(value)

        raise ValidationError,
              "Unknown context type #{value.inspect}. Expected one of #{CONTEXT_TYPES.map(&:inspect).join(", ")}."
      end

      def validate_subject_identifier_type(value)
        return value if SUBJECT_IDENTIFIER_TYPES.include?(value)

        raise ValidationError,
              "Unknown subject identifier type #{value.inspect}. " \
              "Expected one of #{SUBJECT_IDENTIFIER_TYPES.map(&:inspect).join(", ")}."
      end
    end
  end
end
