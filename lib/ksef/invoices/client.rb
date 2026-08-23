# frozen_string_literal: true

module Ksef
  # Invoice operations outside a session (docs/REFERENCE.md §3, DESIGN.md §6.6).
  #
  # Only the download route is here. Query, search and package export are 0.2, and
  # sending happens inside a session, so it lives in {Ksef::Sessions::Online}.
  module Invoices
    # `GET /invoices/ksef/{ksefNumber}` — retrieve an invoice KSeF has accepted.
    #
    # ## Mind the hourly budget
    #
    # 8 req/s but only **64 req/h** (§6.1), which is one of the tightest ceilings in the
    # API — after `POST /invoices/exports` at 20/h. It is a per-document fetch, not a bulk
    # one: pulling a month of invoices this way will exhaust the budget long before the
    # per-second limit ever bites. The package export of 0.2 is the bulk route.
    #
    # Requires the `InvoiceRead` permission, which is one of the two `rake auth:bootstrap`
    # requests for the integration suite.
    class Client
      # @param connection [Faraday::Connection]
      # @param credential [Ksef::Auth::AccessToken, String] anything with `#bearer`
      def initialize(connection, credential)
        @connection = connection
        @credential = credential
      end

      # The invoice as KSeF holds it, returned as the exact bytes received.
      #
      # Verbatim for the same reason a UPO is (§12): this is the archived original of a
      # legal document, and the response is `application/xml` — the connection's JSON
      # middleware matches on content type, so nothing parses or re-encodes it here. Parse
      # a copy with {Ksef::FA3} if you need to read it.
      #
      # This route declares `x-ms-meta-hash` too (§5.5 — four `200` responses carry it), so
      # the bytes are checked against it when it is present. An archived invoice is a legal
      # document; a free integrity check on it is worth taking.
      #
      # @param ksef_number [String, Ksef::KsefNumber]
      # @return [String] FA(3) XML
      # @raise [Ksef::ValidationError] if the number is malformed or fails its checksum
      # @raise [Ksef::IntegrityError] if the published hash does not match the bytes
      def download(ksef_number)
        number = KsefNumber.parse(ksef_number)
        response = @connection.get("invoices/ksef/#{number}") do |request|
          request.headers["Authorization"] = "Bearer #{bearer}"
        end
        verify!(response)

        response.body.to_s
      end

      private

      # Reuses {Ksef::UPO::Document}'s verification rather than reimplementing it: the check
      # is the same SHA-256-against-`x-ms-meta-hash` comparison, and the error a caller sees
      # should be the same one whichever document was fetched. Absent header means
      # unverifiable, not corrupt.
      def verify!(response)
        UPO::Document.new(
          xml: response.body.to_s,
          published_hash: response.headers[UPO::HASH_HEADER],
          source: :api
        ).verify!
      end

      def bearer
        @credential.respond_to?(:bearer) ? @credential.bearer : @credential.to_s
      end
    end
  end
end
