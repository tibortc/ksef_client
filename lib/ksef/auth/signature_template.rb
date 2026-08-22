# frozen_string_literal: true

require "openssl"

module Ksef
  module Auth
    # Renders the `ds:Signature` element, with the `SignedProperties` digest and the
    # `SignatureValue` left empty for {Signer} to fill in once they can be computed.
    #
    # Separated from {Signer} because the two jobs are genuinely different: this one is
    # string templating with fiddly namespace placement, the other is canonicalising,
    # digesting and signing. Rendering from a template rather than assembling nodes is
    # deliberate — the prefixed and default-namespaced elements interleave, and the
    # equivalent Nokogiri namespace calls are markedly harder to read and to get right.
    class SignatureTemplate
      include Xades

      def initialize(certificate:, signing_time:)
        @certificate = certificate
        @signing_time = signing_time
      end

      # @param document_digest [String] Base64 SHA-256 over the canonicalised document
      # @return [String] the signature element, ready to be parsed and adopted
      def render(document_digest)
        <<~XML
          <ds:Signature xmlns:ds="#{DS}" Id="#{SIGNATURE_ID}">
            <ds:SignedInfo>
              <ds:CanonicalizationMethod Algorithm="#{CANONICALIZATION}"/>
              <ds:SignatureMethod Algorithm="#{SIGNATURE_METHOD}"/>
          #{document_reference(document_digest)}
          #{signed_properties_reference}
            </ds:SignedInfo>
            <ds:SignatureValue/>
            <ds:KeyInfo>
              <ds:X509Data>
                <ds:X509Certificate>#{encode(certificate.to_der)}</ds:X509Certificate>
              </ds:X509Data>
            </ds:KeyInfo>
            <ds:Object>#{qualifying_properties}</ds:Object>
          </ds:Signature>
        XML
      end

      private

      attr_reader :certificate, :signing_time

      # `URI=""` means the whole document; the enveloped-signature transform then removes
      # this signature from it, and exclusive c14n normalises what is left. Order matters.
      def document_reference(digest)
        <<~XML.chomp
          <ds:Reference URI="">
            <ds:Transforms>
              <ds:Transform Algorithm="#{ENVELOPED_SIGNATURE}"/>
              <ds:Transform Algorithm="#{CANONICALIZATION}"/>
            </ds:Transforms>
            <ds:DigestMethod Algorithm="#{DIGEST_METHOD}"/>
            <ds:DigestValue>#{digest}</ds:DigestValue>
          </ds:Reference>
        XML
      end

      def signed_properties_reference
        <<~XML.chomp
          <ds:Reference Type="#{SIGNED_PROPERTIES_TYPE}" URI="##{SIGNED_PROPERTIES_ID}">
            <ds:Transforms>
              <ds:Transform Algorithm="#{CANONICALIZATION}"/>
            </ds:Transforms>
            <ds:DigestMethod Algorithm="#{DIGEST_METHOD}"/>
            <ds:DigestValue/>
          </ds:Reference>
        XML
      end

      # `xmlns="#{DS}"` is deliberate, and matches the reference implementation: the
      # qualifying properties mix `xades:`-prefixed elements with xmldsig ones written
      # unprefixed, so `DigestMethod` and `DigestValue` here are in the *xmldsig* namespace
      # despite sitting inside `xades:CertDigest`. Getting that wrong yields a document
      # that looks right and verifies nowhere.
      def qualifying_properties
        <<~XML.strip
          <xades:QualifyingProperties xmlns:xades="#{XADES}" xmlns="#{DS}" Target="##{SIGNATURE_ID}">
                <xades:SignedProperties Id="#{SIGNED_PROPERTIES_ID}">
                  <xades:SignedSignatureProperties>
                    <xades:SigningTime>#{signing_time}</xades:SigningTime>
          #{signing_certificate}
                  </xades:SignedSignatureProperties>
                </xades:SignedProperties>
              </xades:QualifyingProperties>
        XML
      end

      def signing_certificate
        <<~XML.chomp
          <xades:SigningCertificate>
            <xades:Cert>
              <xades:CertDigest>
                <DigestMethod Algorithm="#{DIGEST_METHOD}"/>
                <DigestValue>#{encode(OpenSSL::Digest::SHA256.digest(certificate.to_der))}</DigestValue>
              </xades:CertDigest>
              <xades:IssuerSerial>
                <X509IssuerName>#{issuer_name}</X509IssuerName>
                <X509SerialNumber>#{certificate.serial}</X509SerialNumber>
              </xades:IssuerSerial>
            </xades:Cert>
          </xades:SigningCertificate>
        XML
      end

      # RFC 2253 orders attributes most-specific-first, which is what .NET's
      # `X509Certificate2.Issuer` produces — so a signature from either client describes the
      # same issuer the same way.
      def issuer_name = certificate.issuer.to_s(OpenSSL::X509::Name::RFC2253)

      # `pack("m0")` rather than the base64 library: no line breaks, no dependency.
      def encode(bytes) = [bytes].pack("m0")
    end
  end
end
