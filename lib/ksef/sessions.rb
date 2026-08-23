# frozen_string_literal: true

module Ksef
  # Sessions — the container an invoice is submitted inside (docs/REFERENCE.md §11, §12).
  #
  # An online (interactive) session is opened, carries one or many invoices, and is closed;
  # closing triggers **asynchronous** generation of the collective UPO, so it is not
  # available the moment `close` returns. A session lives **12 hours** from creation and
  # closes itself at `validUntil`. Concurrent sessions are permitted.
  #
  # Batch sessions are 0.2 (DESIGN.md §5.1) and deliberately absent here.
  module Sessions
    # The `formCode` triples, **read from the pinned contract** rather than from
    # `srodowiska.md` — the prose misspells the PEF system codes and omits `FA_RR (1)`
    # entirely (§11.3).
    #
    # Note the space before the bracket in every `systemCode`, and that `value` is *not*
    # the same string: for FA(3) the `value` is `FA`, matching §8's finding that
    # `KodFormularza` is `FA` while `FA (3)` is the `kodSystemowy`.
    FORM_CODES = {
      # TEST accepts FA(2); DEMO and PROD reject it (§11.3). Offered because the transport
      # layer takes any XML, so a caller may have their own FA(2) document — but this gem's
      # builder only produces FA(3).
      fa2: { systemCode: "FA (2)", schemaVersion: "1-0E", value: "FA" }.freeze,
      fa3: { systemCode: "FA (3)", schemaVersion: "1-0E", value: "FA" }.freeze,
      pef3: { systemCode: "PEF (3)", schemaVersion: "2-1", value: "PEF" }.freeze,
      pef_kor3: { systemCode: "PEF_KOR (3)", schemaVersion: "2-1", value: "PEF" }.freeze,
      fa_rr1: { systemCode: "FA_RR (1)", schemaVersion: "1-1E", value: "FA_RR" }.freeze
    }.freeze

    DEFAULT_FORM_CODE = :fa3

    # The UPO format the session will produce, sent as a header on open.
    #
    # **This header is not in the OpenAPI contract at all** — it is sent by both official
    # clients and documented nowhere upstream (§14.6). It is sent here because this gem
    # pins `upo-v4-3.xsd` and nothing else: a session producing 4.2 would yield a document
    # we cannot validate, and Java's own enum proves the server still understands 4.2, so a
    # default exists and is not ours to guess.
    #
    # Being contract-silent, this is the least certain fact the session layer relies on.
    FEATURE_HEADER = "X-KSeF-Feature"
    UPO_VERSION = "upo-v4-3"

    # Reference numbers share the shape `YYYYMMDD-XX-<hex>-<hex>-CC` (§12). Matched loosely
    # and only to keep a garbled value out of a URL path — §12 warns against validating the
    # non-KSeF-number forms against §13's checksum without verifying that first, so this
    # checks the character set and nothing more.
    REFERENCE_NUMBER = /\A[A-Z0-9-]{1,64}\z/

    class << self
      # @param key [Symbol, Hash] a {FORM_CODES} key, or an explicit triple
      # @return [Hash] the `formCode` object for a session-open request
      # @raise [Ksef::ValidationError] on an unknown key
      def form_code(key)
        return key if key.is_a?(Hash)

        FORM_CODES.fetch(key) do
          raise ValidationError,
                "Unknown form code #{key.inspect}. The contract declares " \
                "#{FORM_CODES.keys.map(&:inspect).join(", ")}, or pass an explicit " \
                "{ systemCode:, schemaVersion:, value: } triple."
        end
      end

      # The three fields every `StatusInfo` / `InvoiceStatusInfo` carries, unpacked once
      # rather than in each state object. `details` is nullable in the contract, so it is
      # normalised to a frozen array — a caller should never have to nil-check it.
      #
      # @return [Hash] keyword arguments for a state object
      def status_info(payload)
        status = payload["status"] || {}
        {
          code: status["code"],
          description: status["description"],
          details: Array(status["details"]).freeze
        }
      end

      # @raise [Ksef::ValidationError] if the value could alter the request path
      def reference_number!(value)
        text = value.respond_to?(:reference_number) ? value.reference_number : value.to_s
        return text if REFERENCE_NUMBER.match?(text)

        raise ValidationError,
              "Session reference number #{text.inspect} is not of the documented form " \
              "YYYYMMDD-XX-<hex>-<hex>-CC (docs/REFERENCE.md §12)."
      end
    end
  end
end
