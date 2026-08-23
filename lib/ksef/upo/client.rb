# frozen_string_literal: true

require "uri"

module Ksef
  module UPO
    # Retrieving UPO documents, by either of the two available routes
    # (docs/REFERENCE.md §12, §14.2).
    #
    # ## Two routes, and which to prefer
    #
    # The **pre-signed link** in a session's `upo.pages[]` or an invoice's `upoDownloadUrl`
    # is unmetered, carries an integrity hash, and expires. The **API route** is metered
    # against a budget where `GET /sessions` already allows only 10 requests a minute (§6.1),
    # and publishes no hash.
    #
    # So the link is preferred and the API route is the fallback, which is the resolution
    # §14.2 arrived at — after an earlier revision of the ledger got it backwards and
    # concluded the link should be ignored. {#fetch} implements that preference.
    #
    # ## The connection split is the safety mechanism
    #
    # Requests to a pre-signed link go over `storage`, a connection built by
    # {Ksef::HTTP::Connection.storage} with **no credential and no base URL**. Sending the
    # access token to third-party storage would leak it, and the contract says not to; using
    # a separate connection means no code path here *can*.
    class Client
      # @param connection [Faraday::Connection] the authenticated API connection, for the
      #   metered routes
      # @param credential [Ksef::Auth::AccessToken, String] anything with `#bearer`
      # @param storage [Faraday::Connection] from {Ksef::HTTP::Connection.storage} — must
      #   not carry a credential
      def initialize(connection, credential, storage:)
        @connection = connection
        @credential = credential
        @storage = storage
      end

      # Follows a pre-signed link, verifying the published hash.
      #
      # @param page [Ksef::Sessions::UpoPage, String] a page, or a bare URL
      # @return [Document]
      # @raise [Ksef::IntegrityError] when the bytes do not match `x-ms-meta-hash`
      def download(page)
        url = page.respond_to?(:download_url) ? page.download_url : page.to_s
        raise ValidationError, "No download URL to follow" if url.to_s.empty?

        # No Authorization header is set here, and `@storage` has none by construction.
        response = @storage.get(absolute(url))
        Document.new(
          xml: response.body.to_s,
          published_hash: response.headers[HASH_HEADER],
          source: :storage
        ).verify!
      end

      # The collective UPO for a whole session, over the metered API route.
      def collective(session_reference, upo_reference)
        session = Sessions.reference_number!(session_reference)
        upo = Sessions.reference_number!(upo_reference)

        via_api("sessions/#{session}/upo/#{upo}")
      end

      # One invoice's UPO, addressed by its submission reference.
      def for_invoice(session_reference, invoice_reference)
        session = Sessions.reference_number!(session_reference)
        invoice = Sessions.reference_number!(invoice_reference)

        via_api("sessions/#{session}/invoices/#{invoice}/upo")
      end

      # One invoice's UPO, addressed by its KSeF number.
      #
      # The number is parsed before use, so a mistyped one fails here on its checksum rather
      # than as an opaque 404 (§13).
      def for_ksef_number(session_reference, ksef_number)
        session = Sessions.reference_number!(session_reference)
        number = KsefNumber.parse(ksef_number)

        via_api("sessions/#{session}/invoices/ksef/#{number}/upo")
      end

      # Prefers the unmetered link and falls back to the metered route when it has expired
      # or is missing — the resolution of §14.2, in one call.
      #
      # @param page [Ksef::Sessions::UpoPage]
      # @param session_reference [String] needed for the fallback
      # @return [Document]
      def fetch(page, session_reference:)
        return download(page) unless page.download_url.to_s.empty? || page.expired?

        collective(session_reference, page.reference_number)
      end

      private

      # **The metered routes publish `x-ms-meta-hash` too**, and an earlier version of this
      # method threw it away with a comment claiming they did not. The pinned contract
      # declares the header on all three UPO routes *and* on the invoice download — four
      # `200` responses in total — which §5.5 of the ledger had recorded correctly all along.
      # Discarding an available integrity check on legal proof of receipt was the wrong
      # trade at any price. Corrected 2026-08-23.
      #
      # It is still read defensively rather than required: if the header is absent the
      # document comes back unverifiable rather than failing, which is what {Document}'s
      # `#verifiable?`/`#verified?` split is for.
      def via_api(endpoint)
        response = @connection.get(endpoint) do |request|
          request.headers["Authorization"] = "Bearer #{bearer}"
        end

        Document.new(
          xml: response.body.to_s,
          published_hash: response.headers[HASH_HEADER],
          source: :api
        ).verify!
      end

      # §9 carries this as unverified: whether the live API returns `downloadUrl` absolute or
      # host-relative is unsettled, and `srodowiska.md` says only that a returned URL's
      # *host* matches the environment called. So an absolute URL is used untouched, and a
      # relative one is resolved against the API host rather than guessed at.
      def absolute(url)
        uri = URI.parse(url)
        return url if uri.absolute?

        URI.join(@connection.url_prefix, url).to_s
      rescue URI::InvalidURIError => e
        raise ValidationError, "Malformed UPO download URL: #{e.message}"
      end

      def bearer
        @credential.respond_to?(:bearer) ? @credential.bearer : @credential.to_s
      end
    end
  end
end
