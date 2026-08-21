# frozen_string_literal: true

# The error hierarchy from DESIGN.md §6.7, extended with the 403 and 410 branches the
# API actually returns (docs/REFERENCE.md §7.4).
#
# This file defines many constants and no `Ksef::Errors`, so Zeitwerk cannot manage it —
# `lib/ksef.rb` ignores it and requires it eagerly.
module Ksef
  # Base class for everything this gem raises. Rescue this to catch all of it.
  #
  # `#problem` carries the parsed KSeF error body when the error came from an API
  # response, and is nil for locally-raised errors.
  class Error < StandardError
    # @return [Ksef::ProblemDetails, nil]
    attr_reader :problem

    def initialize(message = nil, problem: nil)
      @problem = problem
      super(message)
    end
  end

  # Invalid or missing client configuration. Raised locally, before any request.
  class ConfigurationError < Error; end

  # Challenge, KSeF-token, signature or JWT problems, including HTTP 401.
  class AuthenticationError < Error; end

  # Raised locally by the FA(3) validator (DESIGN.md §7.7), never by the transport layer.
  class ValidationError < Error; end

  # Any error response from the KSeF API.
  class ApiError < Error
    # @return [Integer, nil] HTTP status
    def status = problem&.status

    # @return [Integer, nil] the first KSeF error code, when the body carried one
    def code = problem&.code

    # @return [Array<String>] flattened detail messages
    def details = problem&.details || []

    # @return [String, nil] the Ministry's correlation id — quote this in support requests
    def trace_id = problem&.trace_id

    # @return [Object, nil] the undecoded response body
    def raw = problem&.raw
  end

  # The invoice was rejected by KSeF on schema or business grounds.
  class InvoiceRejectedError < ApiError; end

  # A session could not be opened, used or closed.
  class SessionError < ApiError; end

  # HTTP 403. Carries a structured reason (docs/REFERENCE.md §5.3) rather than just prose.
  class AuthorizationError < ApiError
    # @return [String, nil] one of `missing-permissions`, `ip-not-allowed`,
    #   `insufficient-resource-access`, `auth-method-not-allowed`,
    #   `security-service-blocked`, `context-type-not-allowed`
    def reason_code = problem&.reason_code

    # @return [Hash] reason-dependent payload, e.g. `requiredAnyOfPermissions`
    def security = problem&.security || {}
  end

  # HTTP 410. The resource existed but is no longer available.
  class ResourceGoneError < ApiError; end

  # HTTP 429. Retryable, but only for idempotent requests (DESIGN.md §6.7).
  class RateLimitedError < ApiError
    # @return [Integer, nil] seconds to wait, from the `Retry-After` header.
    #   Authoritative — the block period is dynamic and lengthens with repeat offences
    #   (docs/REFERENCE.md §6). Never work around a 429 by rotating IPs.
    attr_reader :retry_after

    def initialize(message = nil, problem: nil, retry_after: nil)
      @retry_after = retry_after
      super(message, problem: problem)
    end
  end

  # HTTP 5xx. Not declared anywhere in the OpenAPI contract (docs/REFERENCE.md §5.4), so
  # the body shape is unknown and `#problem` may hold only a raw payload.
  class ServerError < ApiError; end

  # The request exceeded the configured open or read timeout.
  class TimeoutError < Error; end

  # The connection failed, TLS included.
  class ConnectionError < Error; end
end
