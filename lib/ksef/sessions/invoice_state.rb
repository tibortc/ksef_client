# frozen_string_literal: true

module Ksef
  module Sessions
    # The response to `GET /sessions/{ref}/invoices/{invoiceRef}` — the contract's
    # `SessionInvoiceStatusResponse` (docs/REFERENCE.md §12, §12.1).
    #
    # Two fields repay attention.
    #
    # **`upo_download_url` arrives here**, so the per-invoice UPO needs no separate call. It
    # is a pre-signed storage link with the same rules as {UpoPage}: no bearer token, verify
    # `x-ms-meta-hash`, and it expires.
    #
    # **`extensions` is populated only for a duplicate.** On status `440` KSeF returns the
    # *original* submission's KSeF number and session reference, which is what lets a caller
    # reconcile a resend instead of guessing. Nothing else fills it in.
    InvoiceState = Data.define(
      :reference_number, :ksef_number, :invoice_number, :code, :description, :details,
      :extensions, :acquisition_date, :upo_download_url, :upo_download_url_expires_at
    ) do
      def self.from(payload)
        new(
          reference_number: payload["referenceNumber"],
          ksef_number: payload["ksefNumber"],
          invoice_number: payload["invoiceNumber"],
          **Sessions.status_info(payload),
          extensions: (payload.dig("status", "extensions") || {}).freeze,
          acquisition_date: Ksef::Auth.time(payload["acquisitionDate"]),
          upo_download_url: payload["upoDownloadUrl"],
          upo_download_url_expires_at: Ksef::Auth.time(payload["upoDownloadUrlExpirationDate"])
        )
      end

      def in_progress? = InvoiceCodes.in_progress?(code)
      def success? = InvoiceCodes.success?(code)
      def terminal? = InvoiceCodes.terminal?(code)
      def retryable? = InvoiceCodes.retryable?(code)

      # Prefers KSeF's own wording; falls back to our table when it sends none.
      def explain = description.to_s.empty? ? InvoiceCodes.describe(code) : description

      def duplicate? = code == InvoiceCodes::DUPLICATE
      def original_ksef_number = extensions["originalKsefNumber"]
      def original_session_reference = extensions["originalSessionReferenceNumber"]

      # Parsed rather than returned raw, so the CRC-8 is checked and the acceptance date is
      # a Date. `nil` until the invoice is accepted.
      #
      # @return [Ksef::KsefNumber, nil]
      def ksef_number_parsed = ksef_number.nil? ? nil : KsefNumber.parse(ksef_number)

      def to_s = reference_number.to_s
    end
  end
end
