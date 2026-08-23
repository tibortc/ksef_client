# frozen_string_literal: true

module Ksef
  module Sessions
    # The response to `GET /sessions/{ref}` — the contract's `SessionStatusResponse`
    # (docs/REFERENCE.md §12).
    #
    # The transition worth understanding is `170` → `200`. Closing a session starts
    # **asynchronous** generation of the collective UPO, so "closed" is one step short of
    # "the UPO exists" — {#closed?} and {#success?} are deliberately separate, and
    # {#upo_pages} is empty until the latter.
    SessionState = Data.define(
      :reference_number, :code, :description, :details, :created_at, :updated_at,
      :valid_until, :invoice_count, :successful_count, :failed_count, :upo_pages
    ) do
      def self.from(payload, reference_number)
        new(
          reference_number: reference_number,
          **Sessions.status_info(payload),
          created_at: Ksef::Auth.time(payload["dateCreated"]),
          updated_at: Ksef::Auth.time(payload["dateUpdated"]),
          valid_until: Ksef::Auth.time(payload["validUntil"]),
          invoice_count: payload["invoiceCount"],
          successful_count: payload["successfulInvoiceCount"],
          failed_count: payload["failedInvoiceCount"],
          upo_pages: Array(payload.dig("upo", "pages")).map { |page| UpoPage.from(page) }.freeze
        )
      end

      def in_progress? = SessionCodes.in_progress?(code)
      def success? = SessionCodes.success?(code)
      def terminal? = SessionCodes.terminal?(code)

      # Closed, but the collective UPO is still being generated — not the end state.
      def closed? = SessionCodes.closed?(code)

      # The symmetric key was rejected at open, so nothing in this session was readable.
      # Distinct from a per-invoice decryption failure, which is the AES payload rather than
      # the RSA-OAEP key wrap.
      def key_rejected? = SessionCodes.key_rejected?(code)

      # Prefers KSeF's own wording; falls back to our table when it sends none.
      def explain = description.to_s.empty? ? SessionCodes.describe(code) : description

      def to_s = reference_number.to_s
    end
  end
end
