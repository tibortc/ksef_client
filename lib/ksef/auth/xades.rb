# frozen_string_literal: true

require "nokogiri"

module Ksef
  module Auth
    # The namespace URIs and algorithm identifiers of the XAdES signature
    # (docs/REFERENCE.md §4.3).
    #
    # Its own module so that {Signer} and {SignatureTemplate} share one definition rather
    # than one referring to the other's constants. Included rather than referenced, so
    # `Signer::DS` keeps resolving — these names are part of the public vocabulary and are
    # asserted directly in the specs.
    module Xades
      # Read from pinned artifacts, not from memory: `spec/fixtures/xades/` holds the
      # schemas upstream redistributes, and these are their target namespaces (§4.3).
      DS = "http://www.w3.org/2000/09/xmldsig#"
      XADES = "http://uri.etsi.org/01903/v1.3.2#"

      # Every one of these appears in the Ministry's allow-list in `auth/podpis-xades.md`,
      # so the combination needs no further verification (§4.3).
      CANONICALIZATION = "http://www.w3.org/2001/10/xml-exc-c14n#"
      SIGNATURE_METHOD = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
      DIGEST_METHOD = "http://www.w3.org/2001/04/xmlenc#sha256"
      ENVELOPED_SIGNATURE = "http://www.w3.org/2000/09/xmldsig#enveloped-signature"

      # The one identifier the allow-list does not state. Fixed by ETSI TS 101 903 and
      # taken from `ksef-client-csharp`'s `SignatureService.SignedPropertiesType`; ledgered
      # in §4.3 with that provenance rather than treated as common knowledge.
      SIGNED_PROPERTIES_TYPE = "http://uri.etsi.org/01903#SignedProperties"

      C14N_MODE = Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0

      SIGNATURE_ID = "Signature"
      SIGNED_PROPERTIES_ID = "SignedProperties"

      XPATH_NAMESPACES = { "ds" => DS, "xades" => XADES }.freeze
    end
  end
end
