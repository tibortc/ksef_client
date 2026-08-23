# frozen_string_literal: true

module Ksef
  module Sessions
    # Status codes for a session as a whole (docs/REFERENCE.md §12.1).
    #
    # **Interactive and batch sessions have different tables**, and the contract states them
    # separately. These are the *interactive* codes; the batch-only ones are named below but
    # not interpreted, since batch is 0.2.
    #
    # ## What the codes are actually for
    #
    # Closing a session starts **asynchronous** generation of the collective UPO (§11), so
    # the interesting transition is `170` → `200`: closed, then processed. The UPO is not
    # available at `170`. Anyone waiting for proof of receipt is waiting for `200`, which is
    # why {closed?} exists separately from {success?} — a caller that stops at "closed" has
    # stopped one step early.
    #
    # Same `code < 200` rule as {InvoiceCodes}, and note that interactive sessions have **no
    # `150`** at all: a poller written against the batch table waits for a code that never
    # arrives.
    module SessionCodes
      OPEN = 100
      CLOSED = 170
      SUCCESS = 200
      KEY_DECRYPTION_ERROR = 415
      CANCELLED = 440
      NO_VALID_INVOICES = 445
      UNKNOWN_ERROR = 500

      # Declared by the contract for **batch** sessions only. Listed so a code seen in the
      # wild can be named rather than reported as unrecognised, and so nobody re-derives
      # them; batch handling itself is 0.2.
      BATCH_PROCESSING = 150
      BATCH_PACKAGE_ERROR = 405
      BATCH_INVOICE_LIMIT_EXCEEDED = 420
      BATCH_DECOMPRESSION_ERROR = 430
      BATCH_PART_DECRYPTION_ERROR = 435

      DESCRIPTIONS = {
        OPEN => "session open",
        CLOSED => "session closed — the collective UPO is still being generated",
        SUCCESS => "session processed successfully",
        KEY_DECRYPTION_ERROR => "KSeF could not decrypt the symmetric key supplied at open",
        CANCELLED => "session cancelled — no invoices were sent",
        NO_VALID_INVOICES => "verification failed: the session carried no valid invoices",
        UNKNOWN_ERROR => "unknown error",
        BATCH_PROCESSING => "batch session processing",
        BATCH_PACKAGE_ERROR => "batch: package element verification failed",
        BATCH_INVOICE_LIMIT_EXCEEDED => "batch: invoice-per-session limit exceeded",
        BATCH_DECOMPRESSION_ERROR => "batch: archive decompression failed",
        BATCH_PART_DECRYPTION_ERROR => "batch: archive part decryption failed"
      }.freeze

      class << self
        def in_progress?(code) = !code.nil? && code < SUCCESS
        def success?(code) = code == SUCCESS
        def terminal?(code) = !in_progress?(code)

        # Closed but not yet processed. Distinct from {success?} because the collective UPO
        # does not exist yet at this point.
        def closed?(code) = code == CLOSED

        # `415` here is the **RSA-OAEP key wrap** failing, not the AES payload — that is
        # {InvoiceCodes::DECRYPTION_ERROR}, per invoice. The pair localises a crypto fault
        # to either the key or the document, which is worth keeping distinct.
        def key_rejected?(code) = code == KEY_DECRYPTION_ERROR

        def describe(code) = DESCRIPTIONS.fetch(code, "unrecognised session status code #{code}")
      end
    end
  end
end
