# frozen_string_literal: true

module Ksef
  module Sessions
    # The three HTTP calls of an interactive session: open, send, close
    # (docs/REFERENCE.md §11).
    #
    # Deliberately thin and **stateless**, exactly like {Ksef::Auth::Client}: it maps
    # requests and responses and holds no session of its own. That shape is not a guess —
    # both official clients do the same, threading the session reference through as a
    # parameter and offering no session object at all. Deciding *when* to open a session,
    # and composing open-send-close into one call, belongs a layer up in {Ksef::Client}.
    #
    # ## The encryptor travels with the session, not with each send
    #
    # Recorded as a decision at docs/REFERENCE.md §11.2a, alongside the rest of the
    # session-layer choices upstream does not make for us.
    #
    # {Session} carries the {Ksef::Crypto::Encryptor} that opened it. That is the single
    # most important design decision here. The symmetric key is agreed *once*, at open,
    # and every invoice in the session is encrypted under it — so sending an invoice
    # encrypted with a different key produces a payload KSeF cannot decrypt, and the only
    # symptom is per-invoice status **435, "błąd odszyfrowania pliku"** (§12.1), arriving
    # asynchronously, long after the call returned 202.
    #
    # Binding the encryptor to the session at open time makes that mistake unrepresentable
    # rather than merely documented — the same reasoning that makes
    # {Ksef::Crypto::Encryptor#seal} produce both digests together.
    class Online
      # `POST /sessions/online` — 201. The session reference and the moment it dies.
      Session = Data.define(:reference_number, :valid_until, :encryptor) do
        # Twelve hours from creation (§11); the API closes it automatically at this point,
        # so a long-running batch should check rather than assume.
        def expired?(now = Time.now) = !valid_until.nil? && valid_until <= now

        def to_s = reference_number
      end

      # `POST /sessions/online/{ref}/invoices` — 202. The *invoice's* reference number,
      # which is what the per-invoice status and UPO endpoints are keyed on.
      Submission = Data.define(:reference_number) do
        def self.from(payload) = new(reference_number: payload["referenceNumber"])

        def to_s = reference_number
      end

      # @param connection [Faraday::Connection] usually from {Ksef::HTTP::Connection.build}
      # @param credential [Ksef::Auth::AccessToken, String] anything responding to `#bearer`,
      #   or a bare token string. Asked for the bearer per request rather than once, so a
      #   long session picks up a proactive refresh (§4.2).
      def initialize(connection, credential)
        @connection = connection
        @credential = credential
      end

      # Opens a session. "Lightweight and synchronous" per §11 — but not free: a session
      # opened and never used is cancelled with status 440, "nie przesłano faktur" (§12.1).
      #
      # @param encryptor [Ksef::Crypto::Encryptor] generates the session's symmetric key;
      #   bound to the returned {Session} so every send uses the same one
      # @param certificate [Ksef::Crypto::Certificate] from
      #   {Ksef::Crypto::PublicKeys#symmetric_key_encryption}
      # @param form_code [Symbol, Hash] a {Sessions::FORM_CODES} key
      # @param upo_version [String, nil] the {Sessions::UPO_VERSION} header; `nil` omits it
      #   and accepts whatever the server defaults to
      # @return [Session]
      def open(encryptor:, certificate:, form_code: DEFAULT_FORM_CODE, upo_version: UPO_VERSION)
        body = {
          formCode: Sessions.form_code(form_code),
          encryption: encryptor.encryption_info(certificate)
        }
        headers = upo_version.nil? ? {} : { FEATURE_HEADER => upo_version }
        payload = post("sessions/online", body: body, headers: headers).body

        Session.new(
          reference_number: payload["referenceNumber"],
          valid_until: Ksef::Auth.time(payload["validUntil"]),
          encryptor: encryptor
        )
      end

      # Encrypts an invoice and submits it. Returns as soon as KSeF accepts the *upload* —
      # a 202, not an acceptance of the invoice. Whether the invoice itself is accepted
      # arrives later, per invoice, via the status endpoints (§12.1).
      #
      # The four integrity values of §11.1 all come from one {Ksef::Crypto::Encryptor#seal}
      # call, so the plaintext hash cannot be computed over different bytes than the
      # ciphertext hash.
      #
      # @param session [Session] from {#open}
      # @param invoice [String, #to_xml] the FA(3) document
      # @param offline_mode [Boolean] declares the taxpayer's "offline" invoicing mode
      # @param corrected_invoice_hash [String, nil] base64 SHA-256 of the invoice being
      #   corrected; required for a *technical* correction
      # @return [Submission]
      def send_invoice(session, invoice, offline_mode: false, corrected_invoice_hash: nil)
        # Serialised once. What gets hashed has to be exactly what gets encrypted, so the
        # bytes are settled here and never re-derived.
        xml = invoice.respond_to?(:to_xml) ? invoice.to_xml : invoice.to_s
        body = integrity(session.encryptor.seal(xml))
        body[:offlineMode] = true if offline_mode
        body[:hashOfCorrectedInvoice] = corrected_invoice_hash if corrected_invoice_hash

        Submission.from(post(path(session, "invoices"), body: body).body)
      end

      # Closes the session, which starts **asynchronous** generation of the collective UPO
      # (§11). The UPO is not available when this returns; poll the session status for
      # `upo.pages[]`.
      #
      # @return [nil] the API answers 204 with no body
      def close(session)
        post(path(session, "close"))
        nil
      end

      private

      # The four integrity values of §11.1, all from one `#seal`, so the two hashes cannot
      # end up computed over different bytes.
      def integrity(sealed)
        {
          invoiceHash: sealed.plaintext_digest.base64,
          invoiceSize: sealed.plaintext_digest.size,
          encryptedInvoiceHash: sealed.ciphertext_digest.base64,
          encryptedInvoiceSize: sealed.ciphertext_digest.size,
          encryptedInvoiceContent: sealed.content
        }
      end

      def path(session, suffix)
        "sessions/online/#{Sessions.reference_number!(session)}/#{suffix}"
      end

      def post(endpoint, body: nil, headers: {})
        @connection.post(endpoint) do |request|
          request.headers["Authorization"] = "Bearer #{bearer}"
          headers.each { |name, value| request.headers[name] = value }
          request.body = body unless body.nil?
        end
      end

      # A {Ksef::Auth::AccessToken} refreshes itself here if it has gone stale, which is why
      # the bearer is fetched per request rather than captured at construction.
      def bearer
        @credential.respond_to?(:bearer) ? @credential.bearer : @credential.to_s
      end
    end
  end
end
