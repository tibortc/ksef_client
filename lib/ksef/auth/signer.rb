# frozen_string_literal: true

require "nokogiri"
require "openssl"

module Ksef
  module Auth
    # Produces the XAdES-BES enveloped signature that `POST /auth/xades-signature`
    # requires (docs/REFERENCE.md §4.3).
    #
    # The algorithms come from {Xades} and the XML from {SignatureTemplate}; what lives here
    # is the part that has to be exactly right — what gets canonicalised, in what order, and
    # over which bytes.
    #
    # ## Why this signs a String and returns a String
    #
    # A digest over "the document" has to match what the *verifier* computes after parsing
    # the bytes we send. Nokogiri's `to_xml` pretty-prints on output without adding text
    # nodes to the tree, so an in-memory tree and its serialised form can canonicalise
    # differently — the classic XML-DSig footgun. Signing the serialised bytes and emitting
    # them without reformatting removes the discrepancy entirely. `ksef-client-csharp` deals
    # with the same problem by setting `PreserveWhitespace = true`.
    class Signer
      include Xades

      # Emit exactly the bytes that were signed: `AS_XML` alone excludes `FORMAT`, so
      # nothing is re-indented. Passing the default would silently invalidate every
      # signature this produces.
      SAVE_OPTIONS = Nokogiri::XML::Node::SaveOptions::AS_XML

      # `SigningTime` is backdated by a minute, lifted from `ksef-client-csharp`'s
      # `CertificateTimeBuffer = TimeSpan.FromMinutes(-1)`. It is unexplained there but is
      # plainly a clock-skew guard: a signing time fractionally in the future relative to
      # the server's clock invites rejection, and being a minute early costs nothing.
      CLOCK_SKEW_SECONDS = 60

      attr_reader :certificate

      # @param certificate [OpenSSL::X509::Certificate] must meet the subject requirements
      #   of §4.4
      # @param key [OpenSSL::PKey::RSA] its private key
      # @param signing_time [Time, nil] override, for deterministic tests
      # @param clock_skew [Integer] seconds to backdate `SigningTime` by
      def initialize(certificate:, key:, signing_time: nil, clock_skew: CLOCK_SKEW_SECONDS)
        @certificate = certificate
        @key = key
        @signing_time = signing_time
        @clock_skew = clock_skew
        verify_key_matches_certificate
      end

      # @param input [String, #to_xml] the unsigned `AuthTokenRequest`
      # @param validate [Boolean] check against the auth schema first. On by default:
      #   signing is expensive and a malformed document is cheap to catch. It has to happen
      #   *before* signing, because a signed document can never be schema-valid (§14.5) —
      #   the schema's sequence has no `xsd:any`, so the very signature the API demands
      #   counts as an unexpected element.
      # @return [String] the document with a `ds:Signature` appended to its root
      # @raise [Ksef::ValidationError]
      def sign(input, validate: true)
        xml = input.respond_to?(:to_xml) ? input.to_xml : input.to_s
        document = Nokogiri::XML(xml)
        raise ValidationError, "Cannot sign: the document has no root element" if document.root.nil?

        Validator.validate!(xml) if validate

        # Computed before the signature exists, which is exactly what the
        # enveloped-signature transform reproduces for the verifier.
        document.root.add_child(signature_for(digest(document.canonicalize(C14N_MODE))))
        seal(document)
        document.to_xml(save_with: SAVE_OPTIONS)
      end

      private

      # The template declares every namespace it uses, so it needs no ancestor context and
      # `add_child` can adopt it straight from its own document.
      def signature_for(document_digest)
        template = SignatureTemplate.new(certificate: certificate, signing_time: signing_time)
        Nokogiri::XML(template.render(document_digest)).root
      end

      # Order is not optional. `SignedProperties` must be digested in its final position —
      # exclusive c14n pulls in the namespace declarations it inherits — and `SignedInfo`
      # can only be signed once both of its digests are in place.
      def seal(document)
        properties = at(document, "//xades:SignedProperties")
        at(document, "//ds:Reference[@Type]/ds:DigestValue").content =
          digest(properties.canonicalize(C14N_MODE))

        signed_info = at(document, "//ds:SignedInfo")
        at(document, "//ds:SignatureValue").content =
          encode(@key.sign("SHA256", signed_info.canonicalize(C14N_MODE)))
      end

      def at(document, xpath)
        document.at_xpath(xpath, XPATH_NAMESPACES) ||
          raise(ValidationError, "Malformed signature template: #{xpath} not found")
      end

      def signing_time
        ((@signing_time || Time.now).utc - @clock_skew).strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      def digest(bytes) = encode(OpenSSL::Digest::SHA256.digest(bytes))

      def encode(bytes) = [bytes].pack("m0")

      # Signing with a mismatched key yields a perfectly well-formed document that fails
      # only at the far end, with an error that will not say why.
      def verify_key_matches_certificate
        return if certificate.check_private_key(@key)

        raise ValidationError, "The private key does not match the certificate's public key"
      end
    end
  end
end
