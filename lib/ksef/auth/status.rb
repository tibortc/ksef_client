# frozen_string_literal: true

module Ksef
  module Auth
    # Status codes returned by `GET /auth/{referenceNumber}` in `StatusInfo.code`.
    #
    # These are *not* HTTP statuses — they travel inside a 200 response and describe the
    # asynchronous authentication operation.
    #
    # **Sourced from the pinned OpenAPI contract**, whose
    # `AuthenticationOperationStatusResponse.status` description carries the complete table
    # (docs/REFERENCE.md §4.8). An earlier revision credited
    # `AuthenticationStatusCodeResponse.cs` in `ksef-client-csharp` and treated the list as a
    # reference-implementation constant. That understated it: the contract is a first-tier
    # artifact, and reading it added {BLOCKED} — which the C# list does not have — while
    # showing that `400` and `401` are C#-only and not contract codes at all.
    module Status
      IN_PROGRESS = 100
      SUCCESS = 200
      NO_PERMISSIONS = 415
      REVOKED = 425
      TOKEN_ERROR = 450
      CERTIFICATE_ERROR = 460
      DECEASED_USER = 470
      BLOCKED = 480
      UNKNOWN_ERROR = 500
      CANCELLED = 550

      # Present in `ksef-client-csharp`'s enum but **not** in the contract's table. Kept
      # because the server may still send them and a named constant beats a bare integer,
      # but do not treat their absence from the contract as an oversight on our part.
      BAD_REQUEST = 400
      UNAUTHORIZED = 401

      # Several distinct causes share one code — the contract lists **eight** distinct 450
      # details (a malformed, mistimed, revoked or inactive token, plus a bad challenge, bad
      # encryption, bad encoding, and a token unusable in the requested context) and six for
      # 460. The distinction arrives only in `StatusInfo#description`, which is why
      # {OperationStatus#explain} prefers the server's wording over this table.
      DESCRIPTIONS = {
        IN_PROGRESS => "authentication in progress",
        SUCCESS => "authentication succeeded",
        BAD_REQUEST => "bad request",
        UNAUTHORIZED => "unauthorized",
        NO_PERMISSIONS => "failed: the subject holds no permissions in this context",
        REVOKED => "authentication and its refresh tokens were revoked",
        TOKEN_ERROR => "failed: token invalid, mistimed, revoked, inactive, wrongly encrypted or " \
                       "encoded, or not usable in this context",
        CERTIFICATE_ERROR => "failed: certificate invalid, untrusted, revoked, suspended or malformed",
        DECEASED_USER => "failed: authorisation methods of a deceased person",
        BLOCKED => "blocked: suspected security incident — contact the Ministry of Finance, do not retry",
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
