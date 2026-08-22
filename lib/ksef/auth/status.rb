# frozen_string_literal: true

module Ksef
  module Auth
    # Status codes returned by `GET /auth/{referenceNumber}` in `StatusInfo.code`.
    #
    # These are *not* HTTP statuses — they travel inside a 200 response and describe the
    # asynchronous authentication operation. The values come from
    # `AuthenticationStatusCodeResponse.cs` in `ksef-client-csharp` (retrieved 2026-08-22);
    # the Ministry's prose documents only "in progress" and "succeeded" by name, and says
    # the full list "will be available in the endpoint's technical documentation"
    # (docs/REFERENCE.md §4.8).
    module Status
      IN_PROGRESS = 100
      SUCCESS = 200
      BAD_REQUEST = 400
      UNAUTHORIZED = 401
      NO_PERMISSIONS = 415
      REVOKED = 425
      TOKEN_ERROR = 450
      CERTIFICATE_ERROR = 460
      DECEASED_USER = 470
      UNKNOWN_ERROR = 500
      CANCELLED = 550

      # Several distinct causes share one code — 450 covers a token that is malformed,
      # out of time, revoked or inactive, and 460 covers six certificate problems. The
      # human-readable distinction arrives in `StatusInfo#description`, not in the code.
      DESCRIPTIONS = {
        IN_PROGRESS => "authentication in progress",
        SUCCESS => "authentication succeeded",
        BAD_REQUEST => "bad request",
        UNAUTHORIZED => "unauthorized",
        NO_PERMISSIONS => "failed: the subject holds no permissions in this context",
        REVOKED => "authentication and its refresh tokens were revoked",
        TOKEN_ERROR => "failed: token invalid, expired, revoked or inactive",
        CERTIFICATE_ERROR => "failed: certificate invalid, untrusted, revoked, suspended or malformed",
        DECEASED_USER => "failed: authorisation methods of a deceased person",
        UNKNOWN_ERROR => "unknown error",
        CANCELLED => "cancelled by the system; retry later"
      }.freeze

      # The only code that means "keep polling". Anything else is terminal — treating an
      # unrecognised code as retryable would poll forever against a dead operation.
      def self.in_progress?(code) = code == IN_PROGRESS
      def self.success?(code) = code == SUCCESS
      def self.terminal?(code) = !in_progress?(code)

      # `550` is the system cancelling its own work and inviting a retry, which is a
      # different proposition from a rejected certificate.
      def self.retryable?(code) = code == CANCELLED

      def self.describe(code) = DESCRIPTIONS.fetch(code, "unrecognised status code #{code}")
    end
  end
end
