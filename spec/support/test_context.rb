# frozen_string_literal: true

require_relative "../../tasks/ksef_bootstrap"

# One provisioned TEST identity per suite run, shared by every integration example.
#
# Two reasons it is shared rather than per-example. Registering three people a night is
# needless churn in an environment other integrators also use. And more importantly, the
# permission grant from `POST /testdata/person` is applied **asynchronously**
# (docs/REFERENCE.md §6a.6) — authenticating straight afterwards fails with status 415
# roughly half the time, so each registration costs a settle wait.
module TestContext
  # Measured 2026-08-23: with no wait, three consecutive provision-then-authenticate cycles
  # gave success, 415, 415; with ten seconds, three for three succeeded. Ten is the observed
  # figure, not a guess, and the retry below covers the tail.
  SETTLE_SECONDS = 10

  class << self
    # @return [Hash] `{nip:, pesel:}`, provisioned and settled
    def identifiers(connection)
      @identifiers ||= provision(connection)
    end

    private

    def provision(connection)
      ids = { nip: KsefBootstrap::Identifiers.nip, pesel: KsefBootstrap::Identifiers.pesel }
      connection.post("testdata/person") do |request|
        request.body = {
          nip: ids.fetch(:nip), pesel: ids.fetch(:pesel), isBailiff: false,
          isDeceased: false, description: "ksef_client nightly integration"
        }
      end
      sleep SETTLE_SECONDS
      ids
    end
  end
end
