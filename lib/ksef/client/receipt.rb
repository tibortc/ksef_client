# frozen_string_literal: true

module Ksef
  class Client
    # What {Ksef::Client#send_invoice} returns: proof that KSeF accepted the *upload*, and
    # the pair of references needed to find out what became of the invoice.
    #
    # ## Why `#reference` returns the whole object
    #
    # DESIGN.md §8's contract reads `client.wait_until_accepted(result.reference)`, which
    # looks like it wants a single string. It cannot be one: every status and UPO endpoint is
    # keyed on **both** the session and the invoice (`GET /sessions/{ref}/invoices/{ref}`), so
    # an invoice reference on its own cannot look anything up.
    #
    # Rather than bend the API into passing two arguments, or hiding the session on a client
    # that has to stay thread-safe, `#reference` returns `self` — because the pair genuinely
    # *is* the reference of a submission. §8's snippet then runs verbatim, and nothing has to
    # remember which session an invoice went through.
    #
    # Note what this is **not**: acceptance. `POST .../invoices` answers `202`, meaning the
    # upload was taken, and whether the invoice itself is accepted arrives asynchronously
    # (§12.1). {Ksef::Client#wait_until_accepted} is what settles that.
    Receipt = Data.define(:session_reference, :invoice_reference, :session_valid_until) do
      # See the class note: the pair is the reference.
      def reference = self

      # The invoice's own reference number, which is what a human quotes.
      def to_s = invoice_reference.to_s

      # The session closes itself at this point (§11), after which the collective UPO is
      # generated. Exposed because a long batch may want to check rather than assume.
      def session_expired?(now = Time.now)
        !session_valid_until.nil? && session_valid_until <= now
      end
    end
  end
end
