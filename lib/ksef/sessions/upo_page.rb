# frozen_string_literal: true

module Ksef
  module Sessions
    # One page of a collective UPO (docs/REFERENCE.md §12, §14.2).
    #
    # A collective UPO holds **at most 10 000 invoice entries**, which is why a session's
    # `upo.pages` is an array: a client that reads only the first page silently loses proof
    # of receipt for every invoice beyond it.
    #
    # `download_url` is a **pre-signed storage link, not an API route**. Follow it as an
    # opaque URI, send **no** bearer token — sending one leaks the credential to third-party
    # storage — and verify the `x-ms-meta-hash` header against the bytes received. It is
    # regenerated on every status query and expires at {#expires_at}, so it must never be
    # logged or persisted as a durable reference.
    UpoPage = Data.define(:reference_number, :download_url, :expires_at) do
      def self.from(payload)
        new(
          reference_number: payload["referenceNumber"],
          download_url: payload["downloadUrl"],
          expires_at: Ksef::Auth.time(payload["downloadUrlExpirationDate"])
        )
      end

      def expired?(now = Time.now) = !expires_at.nil? && expires_at <= now

      # The link is credential-bearing, so it stays out of any log line by default.
      def to_s = reference_number.to_s

      def inspect
        "#<data Ksef::Sessions::UpoPage reference_number=#{reference_number.inspect} " \
          "download_url=[PRE-SIGNED] expires_at=#{expires_at.inspect}>"
      end
    end
  end
end
