# frozen_string_literal: true

module Ksef
  # The facade — DESIGN.md §8's public API contract.
  #
  #     client = Ksef::Client.new(
  #       env:  :test,
  #       auth: Ksef::Auth::Token.new(context_nip: "9999999999", token: ENV["KSEF_TOKEN"])
  #     )
  #
  #     result = client.send_invoice(invoice)
  #     status = client.wait_until_accepted(result.reference)
  #     status.ksef_number
  #     upo    = client.upo(result.reference)
  #
  # Everything below the facade is usable directly — {Sessions::Online}, {Sessions::Status},
  # {UPO::Client} and {Auth::Client} are all public, and a caller who wants the granular
  # calls should reach for them. This assembles them into the twenty-line path.
  #
  # ## Authentication happens once, lazily, and under a mutex
  #
  # Constructing a client performs no I/O. The first call that needs a credential runs the
  # whole KSeF-token flow — challenge, encrypt, submit, poll, redeem — and hands the result
  # to {Auth::AccessToken}, which then refreshes itself at ~80% of its lifetime. A burst of
  # threads produces one authentication, not one each, because the check happens inside the
  # lock.
  #
  # ## Thread safety
  #
  # A single instance is safe to share (DESIGN.md §5.2), and the design is what makes that
  # true rather than a promise about it. The configuration is frozen at construction; the
  # Faraday connections are shared and stateless; the only mutable state is the memoised
  # credential, guarded by one mutex. **No session is ever held on the client** — that was
  # the deciding argument for opening a fresh one per {#send_invoice} (§11.2a), since a
  # session cached here would be mutable state two threads could submit into at once.
  class Client
    # @param env [Symbol, Ksef::Environments::Environment] `:test`, `:demo` or `:prod`
    # @param auth [Ksef::Auth::Token, Ksef::Auth::AccessToken] a KSeF-token credential to
    #   authenticate with, or an already-redeemed access token
    # @param options [Hash] passed to {Ksef::Configuration} — `logger:`, `timeout:`,
    #   `adapter:`, `proxy:`, `retry_policy:`
    # @param clock [#call] returns the current {Time}; the same injection {Sessions::Status}
    #   and {Crypto::PublicKeys} already take. It reaches {Crypto::PublicKeys}, which decides
    #   whether a published certificate is currently valid, and the {Auth::AccessToken} this
    #   client builds, which decides staleness against the `validUntil` KSeF returned.
    #
    #   **It does not reach an `Auth::AccessToken` passed in as `auth:`** — that one is already
    #   constructed and carries whatever clock it was built with. Build it with the same clock
    #   if you need both pinned.
    #
    #   **This is what makes a recorded cassette replayable.** A recorded access token is
    #   valid for fifteen minutes and {Auth::AccessToken} refreshes at 80% of that, so about
    #   twelve minutes after recording a replay against the real clock reads it as stale and
    #   issues a `POST /auth/token/refresh` that the cassette has no interaction for. Pinning
    #   the clock to the moment of recording replays the flow as it happened, rather than
    #   rewriting what KSeF said (`spec/recorded/session_flow_spec.rb`).
    # @param sleeper [#call] receives a number of seconds; used between polls of the
    #   authentication operation, which is asynchronous ({Auth::Client#wait_until_complete}).
    #   {Sessions::Status#poll} has taken one since it was written and {#wait_until_accepted}
    #   exposes it; this is the same seam for the one poll the facade performs on its own.
    #   A replay wants a no-op — the recorded tier spent eight of its nine seconds asleep
    #   between status calls whose answers were already on disk.
    def initialize(env: :test, auth: nil, clock: -> { Time.now }, sleeper: method(:sleep), **)
      @config = Configuration.new(env: env, auth: auth, **)
      @mutex = Mutex.new
      @clock = clock
      @sleeper = sleeper
      @credential = auth.is_a?(Auth::AccessToken) ? auth : nil
    end

    # @return [Ksef::Configuration] frozen
    attr_reader :config

    # Sends one invoice, in a session of its own.
    #
    # Fresh session per call is the decided default (§11.2a). For more than a handful of
    # invoices use {#session}, which opens one session for all of them. The budgets to compare
    # are the hourly ones: 120 session opens an hour against 180 invoice sends (§6.1). Per
    # minute both are 30, so the saving is real but smaller than it first looks.
    #
    # @param invoice [#to_xml, String] an FA(3) document
    # @param validate [Boolean] run the FA(3) validator first
    # @return [Receipt]
    # @param encryptor [Crypto::Encryptor, nil] see {#session}; for the recorded tier only
    def send_invoice(invoice, validate: true, encryptor: nil)
      session(encryptor: encryptor) { |batch| batch.send_invoice(invoice, validate: validate) }
    end

    # Opens one session, yields a handle, and closes it however the block ends.
    #
    # Closing is what starts generation of the collective UPO (§11), so it matters that it
    # happens — hence a block rather than a returned session.
    #
    # @yieldparam batch [Session]
    # @param encryptor [Crypto::Encryptor, nil] the session's symmetric key. Generated fresh
    #   when omitted, which is what every caller should do — a key is per-session by design
    #   (docs/REFERENCE.md §11.2a) and reusing one across sessions is a step towards reusing
    #   it across *documents*, which is what the per-session binding exists to prevent.
    #
    #   It is injectable for exactly one reason: **the recorded test tier** (DESIGN.md §9.1).
    #   `Encryptor.generate` draws a random key and IV, and RSA-OAEP padding is randomised on
    #   top, so a recorded request body can never be reproduced — a replayed run has to supply
    #   the key the recording used. Without this seam the recorded tier would have to drive
    #   {Sessions::Online} directly and would stop testing the facade a user actually calls.
    # @return the block's value
    def session(form_code: Sessions::DEFAULT_FORM_CODE, upo_version: Sessions::UPO_VERSION,
                encryptor: nil)
      # Wrapped in the §10.2 remediation: certificates are cached for an hour, so an
      # emergency key rotation inside that window makes the cached `publicKeyId` unknown and
      # the open fails with `21470`. `with_key_rotation` re-fetches and re-selects, and the
      # certificate is chosen *inside* the block so the second attempt uses the new key.
      #
      # This is not a retry of a POST in the sense the hard rule forbids: a 21470 means the
      # request was declined outright, so there is no session to duplicate.
      opened = public_keys.with_key_rotation do
        sessions.open(
          encryptor: encryptor || Crypto::Encryptor.generate,
          certificate: public_keys.symmetric_key_encryption,
          form_code: form_code,
          upo_version: upo_version
        )
      end
      yield Session.new(self, opened)
    ensure
      sessions.close(opened) if opened
    end

    # Waits until KSeF has decided about one invoice.
    #
    # @param receipt [Receipt] from {#send_invoice}
    # @return [Ksef::Sessions::InvoiceState] always accepted
    # @raise [Ksef::InvoiceRejectedError] with KSeF's own wording, and the original's
    #   references when the rejection was a duplicate
    # @raise [Ksef::TimeoutError] when the deadline passes with the invoice still processing
    def wait_until_accepted(receipt, **)
      status_client.wait_until_accepted(receipt.session_reference, receipt.invoice_reference, **)
    end

    # The current status of one invoice, without waiting.
    #
    # @return [Ksef::Sessions::InvoiceState]
    def invoice_status(receipt)
      status_client.invoice(receipt.session_reference, receipt.invoice_reference)
    end

    # The UPO for one invoice — the signed proof of receipt. **Archive the bytes verbatim**
    # (§12); {UPO::Document#write} does that.
    #
    # Uses the metered per-invoice route rather than chasing the unmetered pre-signed link,
    # which is the opposite of what §14.2 prefers — deliberately, and only here. Obtaining
    # that link costs a metered status call first, so for a single invoice the direct route
    # is one request against two. The unmetered link earns its keep on *collective* UPOs and
    # in bulk, where {UPO::Client#fetch} is the right entry point.
    #
    # @param receipt [Receipt]
    # @return [Ksef::UPO::Document]
    def upo(receipt)
      upo_client.for_invoice(receipt.session_reference, receipt.invoice_reference)
    end

    # The collective UPO for a whole session, following the unmetered link when it is still
    # valid. Available only after the session has closed *and* finished processing — poll
    # {#session_status} until it reports success, since `170` means closed but not done.
    #
    # @param session_reference [String]
    # @return [Array<Ksef::UPO::Document>] one per page; a collective UPO holds at most
    #   10 000 invoices, and reading only the first page loses proof for the rest (§12)
    def collective_upo(session_reference)
      status_client.session(session_reference).upo_pages.map do |page|
        upo_client.fetch(page, session_reference: session_reference)
      end
    end

    # @return [Ksef::Sessions::SessionState]
    def session_status(session_reference) = status_client.session(session_reference)

    # Downloads an invoice KSeF holds, by its KSeF number.
    #
    # @param ksef_number [String, Ksef::KsefNumber]
    # @return [String] FA(3) XML, verbatim
    def download_invoice(ksef_number) = invoices.download(ksef_number)

    # Runs the FA(3) validator, if the document knows how to validate itself.
    #
    # A raw XML String does not — the transport layer accepts any `#to_xml` or a String
    # (DESIGN.md §5), and refusing one here would break that contract to enforce a check the
    # caller may already have done. But it is still **bytes**, and the byte-level admission
    # rules of docs/REFERENCE.md §15.1 apply to bytes whatever produced them. So a String gets
    # tier 1b: a review on 2026-08-24 pointed out that the gem, handed the poison fixture as a
    # String, would have shipped the very document tier 1 was built to stop — mis-encoded ERP
    # text being precisely the case §15.1 calls likely.
    #
    # Not the schema tier: validating a caller's own XML against FA(3) would reject the batch
    # and RR structures the transport layer is meant to carry.
    #
    # @raise [Ksef::ValidationError]
    def validate_invoice!(invoice)
      return invoice.validate! if invoice.respond_to?(:validate!)
      return unless invoice.is_a?(String)

      issues = FA3::DocumentValidator.errors_for(invoice)
      return if issues.empty?

      raise ValidationError,
            "The XML given is not admissible:\n#{issues.sort.map { |issue| "  - #{issue}" }.join("\n")}"
    end

    # @return [Ksef::Sessions::Online]
    def sessions = @sessions ||= Sessions::Online.new(connection, credential)

    # @return [Ksef::Sessions::Status]
    #
    # Named `status_client` rather than `status` so it cannot be mistaken for
    # {#invoice_status} or {#session_status}, which return an actual status.
    def status_client = @status_client ||= Sessions::Status.new(connection, credential)

    # @return [Ksef::UPO::Client]
    def upo_client
      @upo_client ||= UPO::Client.new(
        connection, credential, clock: @clock, storage: HTTP::Connection.storage(config)
      )
    end

    # @return [Ksef::Invoices::Client]
    def invoices = @invoices ||= Invoices::Client.new(connection, credential)

    # The clock goes here too, and that is not symmetry for its own sake: `#for_usage` filters
    # published certificates on `valid_at?`, so a replay running after they expire finds none
    # and raises. The cassettes' certificates run to 2027-09-29 — pinning only
    # {Auth::AccessToken} would have left the tier a time bomb with a longer fuse.
    #
    # @return [Ksef::Crypto::PublicKeys]
    def public_keys = @public_keys ||= Crypto::PublicKeys.new(connection, clock: @clock)

    # @return [Ksef::Auth::Client]
    def auth = @auth ||= Auth::Client.new(connection)

    # The access token, authenticating first if that has not happened yet.
    #
    # @return [Ksef::Auth::AccessToken]
    def credential
      @mutex.synchronize { @credential ||= authenticate_with_rotation! }
    end

    def inspect = "#<Ksef::Client env=#{config.environment.name.inspect}>"

    private

    def connection = @connection ||= HTTP::Connection.build(config)

    # The KSeF-token flow of §4.5, end to end: submit, poll, redeem. Callers hold the mutex.
    def authenticate!
      initiated = auth.submit_ksef_token(token_request)
      auth.authenticate!(initiated.reference_number, token: initiated.authentication_token,
                                                     sleeper: @sleeper)

      Auth::AccessToken.new(
        auth.redeem(token: initiated.authentication_token), client: auth, clock: @clock
      )
    end

    # A fresh challenge and the key that wraps the token. Both are fetched here rather than
    # cached: the challenge is single-use and lives ten minutes (§4), and the certificate
    # comes from {Crypto::PublicKeys}, which does its own caching.
    def token_request
      credential_token.authentication_request(
        challenge: auth.challenge, certificate: public_keys.token_encryption
      )
    end

    # Authentication consumes a published key too, so it gets the same remediation. The
    # challenge is re-fetched on the second attempt as well, which is correct: challenges are
    # single-use, so replaying one would fail for a different reason.
    def authenticate_with_rotation!
      public_keys.with_key_rotation { authenticate! }
    end

    # A usable credential, or a message saying where one comes from — the failure a caller
    # is most likely to hit on their first attempt.
    def credential_token
      token = config.auth
      return token if token.respond_to?(:authentication_request)

      raise ConfigurationError,
            "Ksef::Client needs auth: a Ksef::Auth::Token (or an already-redeemed " \
            "Ksef::Auth::AccessToken), got #{token.inspect}. A KSeF token is minted by " \
            "POST /tokens after a one-time XAdES authentication (docs/REFERENCE.md §6a.2)."
    end
  end
end
