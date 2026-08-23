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
    def initialize(env: :test, auth: nil, **)
      @config = Configuration.new(env: env, auth: auth, **)
      @mutex = Mutex.new
      @credential = auth.is_a?(Auth::AccessToken) ? auth : nil
    end

    # @return [Ksef::Configuration] frozen
    attr_reader :config

    # Sends one invoice, in a session of its own.
    #
    # Fresh session per call is the decided default (§11.2a). For more than a handful of
    # invoices use {#session}, which opens one session for all of them — the rate budget
    # allows 30 session opens a minute against 180 invoice sends.
    #
    # @param invoice [#to_xml, String] an FA(3) document
    # @param validate [Boolean] run the FA(3) validator first
    # @return [Receipt]
    def send_invoice(invoice, validate: true)
      session { |batch| batch.send_invoice(invoice, validate: validate) }
    end

    # Opens one session, yields a handle, and closes it however the block ends.
    #
    # Closing is what starts generation of the collective UPO (§11), so it matters that it
    # happens — hence a block rather than a returned session.
    #
    # @yieldparam batch [Session]
    # @return the block's value
    def session(form_code: Sessions::DEFAULT_FORM_CODE, upo_version: Sessions::UPO_VERSION)
      opened = sessions.open(
        encryptor: Crypto::Encryptor.generate,
        certificate: public_keys.symmetric_key_encryption,
        form_code: form_code,
        upo_version: upo_version
      )
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
    # A raw XML String does not, and is passed through: the transport layer accepts any
    # `#to_xml` or a String (DESIGN.md §5), and refusing a String here would break that
    # contract to enforce a check the caller may have already done.
    #
    # @raise [Ksef::ValidationError]
    def validate_invoice!(invoice)
      invoice.validate! if invoice.respond_to?(:validate!)
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
      @upo_client ||= UPO::Client.new(connection, credential, storage: HTTP::Connection.storage(config))
    end

    # @return [Ksef::Invoices::Client]
    def invoices = @invoices ||= Invoices::Client.new(connection, credential)

    # @return [Ksef::Crypto::PublicKeys]
    def public_keys = @public_keys ||= Crypto::PublicKeys.new(connection)

    # @return [Ksef::Auth::Client]
    def auth = @auth ||= Auth::Client.new(connection)

    # The access token, authenticating first if that has not happened yet.
    #
    # @return [Ksef::Auth::AccessToken]
    def credential
      @mutex.synchronize { @credential ||= authenticate! }
    end

    def inspect = "#<Ksef::Client env=#{config.environment.name.inspect}>"

    private

    def connection = @connection ||= HTTP::Connection.build(config)

    # The KSeF-token flow of §4.5, end to end: submit, poll, redeem. Callers hold the mutex.
    def authenticate!
      initiated = auth.submit_ksef_token(token_request)
      auth.authenticate!(initiated.reference_number, token: initiated.authentication_token)

      Auth::AccessToken.new(auth.redeem(token: initiated.authentication_token), client: auth)
    end

    # A fresh challenge and the key that wraps the token. Both are fetched here rather than
    # cached: the challenge is single-use and lives ten minutes (§4), and the certificate
    # comes from {Crypto::PublicKeys}, which does its own caching.
    def token_request
      credential_token.authentication_request(
        challenge: auth.challenge, certificate: public_keys.token_encryption
      )
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
