# frozen_string_literal: true

module Ksef
  module Sessions
    # Status codes for one invoice inside a session (docs/REFERENCE.md §12.1).
    #
    # Not HTTP statuses: they travel inside a 200 response, in `InvoiceStatusInfo.code`,
    # and describe how far KSeF has got with that document. **Read from the pinned
    # contract**, whose `SessionInvoiceStatusResponse.status` description carries the full
    # table — not from `InvoiceInSessionStatusCodeResponse.cs`, which lists `400`, `401` and
    # `403` that the contract never declares (the §4.8 lesson, applied).
    #
    # ## Anything below 200 is still in progress
    #
    # The reference clients poll while the code is exactly `150` and return otherwise. That
    # is wrong on the contract's own wording: `100` is "przyjęta do dalszego przetwarzania"
    # — accepted for **further** processing — so an invoice sitting at `100` is undecided and
    # has no KSeF number yet. Stopping there reports a pending invoice as though it were
    # settled.
    #
    # Hence `code < 200` rather than a list of known intermediate codes: an intermediate
    # code upstream adds later is then handled correctly by default. This is the opposite of
    # {Ksef::Auth::Status}'s treat-the-unknown-as-terminal rule, and the asymmetry is
    # deliberate — authentication polls with no deadline, so an unknown code there must not
    # loop for ever, while session polling is deadline-bounded, and "unresolved" is a more
    # honest answer about an invoice than "prematurely final".
    module InvoiceCodes
      ACCEPTED_FOR_PROCESSING = 100
      PROCESSING = 150
      SUCCESS = 200
      SESSION_FAILED = 405
      INVALID_PERMISSIONS = 410
      ATTACHMENT_NOT_ALLOWED = 415
      FILE_VALIDATION_ERROR = 430
      DECRYPTION_ERROR = 435
      DUPLICATE = 440
      SEMANTIC_ERROR = 450
      UNKNOWN_ERROR = 500
      CANCELLED = 550

      DESCRIPTIONS = {
        ACCEPTED_FOR_PROCESSING => "accepted for further processing",
        PROCESSING => "processing",
        SUCCESS => "accepted — the invoice has a KSeF number",
        SESSION_FAILED => "processing cancelled because the session failed",
        INVALID_PERMISSIONS => "invalid permission scope",
        ATTACHMENT_NOT_ALLOWED => "this context may not send an invoice with an attachment",
        FILE_VALIDATION_ERROR => "invoice file verification failed",
        DECRYPTION_ERROR => "KSeF could not decrypt the file — check the session key and the IV",
        DUPLICATE => "duplicate invoice; see #extensions for the original's references",
        SEMANTIC_ERROR => "the invoice document failed semantic verification",
        UNKNOWN_ERROR => "unknown error",
        CANCELLED => "cancelled by the system; retry later"
      }.freeze

      class << self
        def in_progress?(code) = !code.nil? && code < SUCCESS
        def success?(code) = code == SUCCESS
        def terminal?(code) = !in_progress?(code)

        # `550` is the system interrupting its own work and inviting another attempt, which
        # is a different proposition from a rejected document. **Nothing else here is
        # retryable** — least of all {DUPLICATE}, where a retry is what created it.
        def retryable?(code) = code == CANCELLED

        def describe(code) = DESCRIPTIONS.fetch(code, "unrecognised invoice status code #{code}")
      end
    end
  end
end
