# frozen_string_literal: true

module Ksef
  # Authentication against KSeF (docs/REFERENCE.md §4).
  module Auth
    # Both schema versions of the `AuthTokenRequest` document.
    #
    # **2.0 is the default, and that is a deliberate correction.** v2.1 is the newer file,
    # but every piece of available evidence points at 2.0 as what the API actually expects:
    # both official clients bind to it (`[XmlRoot(Namespace = "…/2.0")]` in
    # `AuthenticationTokenRequest.cs`; JAXB classes generated against 2.0 in
    # `ksef-client-java`), the Java client bundles its own copy of the 2.0 schema, and
    # every worked example in `CIRFMF/ksef-api` declares 2.0. Nothing observed so far
    # emits 2.1. See §14.4.
    NAMESPACES = {
      "2.0" => "http://ksef.mf.gov.pl/auth/token/2.0",
      "2.1" => "http://ksef.mf.gov.pl/auth/token/2.1"
    }.freeze

    DEFAULT_SCHEMA_VERSION = "2.0"
  end
end
