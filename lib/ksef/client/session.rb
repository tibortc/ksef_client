# frozen_string_literal: true

module Ksef
  class Client
    # The handle {Ksef::Client#session} yields — one open session, for sending several
    # invoices through deliberately.
    #
    # ## Why batching is opt-in rather than the default
    #
    # `Ksef::Client#send_invoice` opens a fresh session per call (docs/REFERENCE.md §11.2a,
    # decided 2026-08-23). That is the safe default, not the efficient one: a session lives
    # twelve hours and takes ten thousand invoices, so opening one per invoice spends
    # `POST /sessions/online`'s budget of 30/min where a batch would spend one.
    #
    # So this exists for anyone sending more than a handful — and it is a block, not a
    # returned object, because the session must be closed. Closing is what triggers
    # generation of the collective UPO (§11); a session merely abandoned closes itself at
    # `validUntil` up to twelve hours later, and the proof of receipt waits that long with it.
    #
    #     client.session do |batch|
    #       invoices.each { |invoice| batch.send_invoice(invoice) }
    #     end   # ← closed here, whatever happened inside
    #
    # The whole session shares one symmetric key, which is exactly why {Sessions::Online}
    # binds the encryptor to the session rather than taking one per send.
    class Session
      # @return [Ksef::Sessions::Online::Session] the open session, key and all
      attr_reader :opened

      def initialize(client, opened)
        @client = client
        @opened = opened
        @receipts = []
      end

      # Validates, encrypts and submits one invoice into this session.
      #
      # @param invoice [#to_xml, String]
      # @param validate [Boolean] run the FA(3) validator first. On by default: a document
      #   KSeF will reject costs a round trip and a slot in the session, and the local
      #   validator is free (DESIGN.md §7.7).
      # @return [Receipt]
      def send_invoice(invoice, validate: true)
        @client.validate_invoice!(invoice) if validate
        submission = @client.sessions.send_invoice(@opened, invoice)

        Receipt.new(
          session_reference: @opened.reference_number,
          invoice_reference: submission.reference_number,
          session_valid_until: @opened.valid_until
        ).tap { |receipt| @receipts << receipt }
      end

      # Every receipt from this session, in the order they were submitted.
      #
      # Worth keeping: after {Ksef::Client#session} returns, the collective UPO covers
      # exactly these invoices, and a caller that discarded the receipts has no way to ask
      # about any of them individually.
      #
      # @return [Array<Receipt>]
      def receipts = @receipts.dup

      def reference_number = @opened.reference_number

      def to_s = reference_number.to_s
    end
  end
end
