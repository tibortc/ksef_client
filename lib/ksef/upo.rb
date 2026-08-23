# frozen_string_literal: true

module Ksef
  # Urzędowe Poświadczenie Odbioru — the official acknowledgement of receipt
  # (docs/REFERENCE.md §12, §14.2, §14.3).
  #
  # A UPO is an XML document **XAdES-signed by the Ministry of Finance**, and it is the
  # legal proof that KSeF received an invoice. Everything in this namespace is shaped by one
  # consequence of that: the bytes matter more than their meaning.
  #
  # ## Three rules, all of them load-bearing
  #
  # **Archive the bytes verbatim.** Re-serialising a UPO — even losslessly by XML's own
  # rules — can invalidate the Ministry's signature, because a signature covers octets and
  # not an abstract tree. {Document} therefore holds the exact `String` received and offers
  # no pretty-printing, no re-encoding, and no parse-then-emit path.
  #
  # **Never send the access token to a `downloadUrl`.** Those links are pre-signed storage
  # URIs, not API routes; they carry their own authorisation in the query string, and the
  # contract says explicitly not to send the token. {Ksef::HTTP::Connection.storage} exists
  # so that requests to them go over a connection with no credential attached at all.
  #
  # **Verify `x-ms-meta-hash`.** It is the only integrity check available on bytes fetched
  # outside the API, and the artifact is legal proof of receipt. A mismatch raises
  # {Ksef::IntegrityError} rather than being logged and ignored.
  #
  # ## And one trap
  #
  # Validating a received UPO against the bundled schema **rejects every UPO that TEST
  # issues** (§14.3): `upo-v4-3.xsd` fixes `NazwaPodmiotuPrzyjmujacego` to
  # `"Ministerstwo Finansów"`, while the non-production environments append an environment
  # marker. All six of upstream's own worked examples fail upstream's own schema on exactly
  # that element and nothing else. So validation here is a **diagnostic, never a gate** —
  # and never a condition on archiving the bytes.
  module UPO
    # `x-ms-meta-hash` — Azure Blob Storage's header, which is itself the clearest evidence
    # that a `downloadUrl` is storage rather than an API route. Carries the SHA-256 of the
    # document, Base64-encoded.
    HASH_HEADER = "x-ms-meta-hash"

    # Read from the pinned schema's `targetNamespace`, not from memory.
    NAMESPACE = "http://upo.schematy.mf.gov.pl/KSeF/v4-3"

    # The element §14.3 is about. `upo-v4-3.xsd` fixes it to `"Ministerstwo Finansów"`,
    # while every non-production environment appends a marker — TEST sends
    # `"Ministerstwo Finansów - środowisko testowe (TE)"`.
    RECEIVING_PARTY_ELEMENT = "NazwaPodmiotuPrzyjmujacego"
  end
end
