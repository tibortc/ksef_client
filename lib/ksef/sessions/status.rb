# frozen_string_literal: true

module Ksef
  module Sessions
    # Reading session and invoice status, and waiting for it (docs/REFERENCE.md §12).
    #
    # Single-shot calls are always available; the blocking helpers are built on them.
    # Parsing lives in {SessionState} and {InvoiceState}, so this class is only the HTTP
    # calls and the waiting.
    #
    # ## Which endpoint to poll, and why it matters
    #
    # `GET /sessions` — the *list* — is **the tightest budget in the whole API** at 10 req/min
    # (§6.1), against 1200/h for `GET /sessions/{ref}` and the per-invoice endpoint. Polling
    # must never touch the list. This class exposes no list call at all, which is the simplest
    # way to make that mistake impossible rather than merely discouraged.
    #
    # ## Backoff, and why not the reference clients' schedule
    #
    # Capped exponential — 1s, 2s, 4s … 30s — with a five-minute deadline (DESIGN.md §6.5).
    # Both official clients instead poll at a fixed 1 second for up to 60 attempts (§12.2).
    # That is fine for a test utility and wrong for a library: at 1/s a single wait spends 60
    # of the 1200 requests an hour a context gets, and a 60-second ceiling is far too short
    # for a large session. Their *terminal condition* is adopted, with one correction — see
    # {InvoiceCodes} on why `100` also means keep going.
    class Status
      # Seconds. Doubling from the first, clamped at the third.
      INITIAL_INTERVAL = 1
      BACKOFF_FACTOR = 2
      MAX_INTERVAL = 30

      # Overall wall-clock budget for a blocking wait.
      DEFAULT_DEADLINE = 300

      # @param connection [Faraday::Connection]
      # @param credential [Ksef::Auth::AccessToken, String] anything with `#bearer`
      def initialize(connection, credential)
        @connection = connection
        @credential = credential
      end

      # @return [SessionState]
      def session(reference)
        number = Sessions.reference_number!(reference)

        SessionState.from(get("sessions/#{number}").body, number)
      end

      # @return [InvoiceState]
      def invoice(session_reference, invoice_reference)
        session_number = Sessions.reference_number!(session_reference)
        invoice_number = Sessions.reference_number!(invoice_reference)

        InvoiceState.from(get("sessions/#{session_number}/invoices/#{invoice_number}").body)
      end

      # Polls a session until it stops being in progress.
      #
      # This waits for `200`, not for `170`: closing starts asynchronous UPO generation, so
      # a wait that stopped at "closed" would return before the UPO existed.
      #
      # @yieldparam state [SessionState] after each poll, for progress reporting
      # @raise [Ksef::TimeoutError] when the deadline passes with the session still working
      def wait_for_session(reference, **, &)
        poll(-> { session(reference) }, "session #{reference}", **, &)
      end

      # Polls one invoice until it stops being in progress.
      #
      # @raise [Ksef::TimeoutError] when the deadline passes
      def wait_for_invoice(session_reference, invoice_reference, **, &)
        poll(-> { invoice(session_reference, invoice_reference) }, "invoice #{invoice_reference}", **, &)
      end

      # As {#wait_for_invoice}, but insists the invoice was accepted.
      #
      # @return [InvoiceState] always successful
      # @raise [Ksef::InvoiceRejectedError] carrying KSeF's own wording, and the original's
      #   references when the rejection was a duplicate
      def wait_until_accepted(session_reference, invoice_reference, **, &)
        state = wait_for_invoice(session_reference, invoice_reference, **, &)
        return state if state.success?

        raise InvoiceRejectedError, rejection_message(state)
      end

      private

      def rejection_message(state)
        parts = ["Invoice #{state.reference_number} was not accepted: status #{state.code}, #{state.explain}"]
        parts << "(#{state.details.join("; ")})" unless state.details.empty?
        if state.duplicate?
          parts << ". The original is #{state.original_ksef_number} " \
                   "in session #{state.original_session_reference}"
        end
        parts.join(" ").sub(" .", ".")
      end

      # `sleeper` and `clock` are injected so specs neither wait nor need elapsed time.
      def poll(fetch, subject, deadline: DEFAULT_DEADLINE, sleeper: method(:sleep), clock: -> { Time.now })
        started = clock.call
        interval = INITIAL_INTERVAL

        loop do
          state = fetch.call
          yield state if block_given?
          return state if state.terminal?

          elapsed = clock.call - started
          raise TimeoutError, timed_out(subject, state, elapsed) if elapsed + interval > deadline

          sleeper.call(interval)
          interval = [interval * BACKOFF_FACTOR, MAX_INTERVAL].min
        end
      end

      # Says plainly that the operation is unfinished rather than failed — the two call for
      # different responses from a caller, and conflating them invites a needless resend.
      def timed_out(subject, state, elapsed)
        "Gave up waiting for #{subject} after #{elapsed.round}s; it is still #{state.code} " \
          "(#{state.explain}). Raise the deadline: option or poll again later — the operation " \
          "has not failed, only outlasted the wait."
      end

      def get(endpoint)
        @connection.get(endpoint) do |request|
          request.headers["Authorization"] = "Bearer #{bearer}"
        end
      end

      # A {Ksef::Auth::AccessToken} refreshes itself here if stale, which is why the bearer
      # is fetched per request rather than captured at construction.
      def bearer
        @credential.respond_to?(:bearer) ? @credential.bearer : @credential.to_s
      end
    end
  end
end
