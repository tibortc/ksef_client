# frozen_string_literal: true

module Ksef
  # A parsed KSeF error body.
  #
  # KSeF serves errors in two different envelopes and the response `Content-Type` picks
  # between them (docs/REFERENCE.md §5.1): `application/problem+json` is current, while
  # `application/json` returns legacy shapes the spec marks deprecated but which are
  # still live in the wild. This class normalises all of them, and degrades to a raw
  # payload for bodies that are neither (an HTML block page from the WAF in front of the
  # API, for instance).
  ProblemDetails = Data.define(
    :status,
    :title,
    :detail,
    :instance,
    :timestamp,
    :trace_id,
    :entries,
    :reason_code,
    :security,
    :raw
  )

  # Parsing and presentation for {Ksef::ProblemDetails}.
  class ProblemDetails
    # One entry of a 400's `errors[]`. Called `ApiError` in the OpenAPI spec, renamed
    # here to avoid colliding with the {Ksef::ApiError} exception class.
    Entry = Data.define(:code, :description, :details)

    # Only `status` and `raw` are common to every envelope; everything else is absent in
    # at least one of them, so the builders below name only what they actually have.
    DEFAULTS = {
      status: nil, title: nil, detail: nil, instance: nil, timestamp: nil,
      trace_id: nil, entries: [].freeze, reason_code: nil, security: {}.freeze, raw: nil
    }.freeze

    class << self
      # @param status [Integer] HTTP status
      # @param body [Hash, String, nil] decoded JSON body, or the raw string
      # @return [Ksef::ProblemDetails]
      def parse(status:, body:)
        return build(status: status, raw: body) unless body.is_a?(Hash)

        if body["exception"].is_a?(Hash)
          legacy_exception(status, body)
        elsif body["status"].is_a?(Hash)
          legacy_status(status, body)
        else
          problem_json(status, body)
        end
      end

      private

      def build(**attrs) = new(**DEFAULTS, **attrs)

      # The current `application/problem+json` shape.
      def problem_json(status, body)
        build(
          status: body["status"] || status,
          title: body["title"],
          detail: body["detail"],
          instance: body["instance"],
          timestamp: body["timestamp"],
          trace_id: body["traceId"],
          entries: Array(body["errors"]).filter_map { |e| entry_from_api_error(e) },
          reason_code: body["reasonCode"],
          security: body["security"] || {},
          raw: body
        )
      end

      # Deprecated `ExceptionResponse`: details nest under `exception.exceptionDetailList`.
      def legacy_exception(status, body)
        exception = body["exception"]
        entries = Array(exception["exceptionDetailList"]).filter_map { |e| entry_from_exception_detail(e) }

        build(
          status: status,
          title: exception["serviceName"],
          detail: entries.first&.description,
          timestamp: exception["timestamp"],
          # The legacy envelope has no traceId; referenceNumber is its closest analogue.
          trace_id: exception["referenceNumber"],
          entries: entries,
          raw: body
        )
      end

      # Deprecated `TooManyRequestsResponse`: `status` is an object, not an integer.
      def legacy_status(status, body)
        inner = body["status"]
        details = Array(inner["details"])
        entry = Entry.new(code: inner["code"], description: inner["description"], details: details)

        build(
          status: inner["code"] || status,
          title: inner["description"],
          detail: details.first,
          entries: [entry],
          raw: body
        )
      end

      def entry_from_api_error(entry)
        return unless entry.is_a?(Hash)

        Entry.new(
          code: entry["code"],
          description: entry["description"],
          details: Array(entry["details"])
        )
      end

      def entry_from_exception_detail(entry)
        return unless entry.is_a?(Hash)

        Entry.new(
          code: entry["exceptionCode"],
          description: entry["exceptionDescription"],
          details: Array(entry["details"])
        )
      end
    end

    # @return [Integer, nil] the first KSeF error code, when the body carried one
    def code = entries.first&.code

    # @return [Array<String>] every detail message, across all entries
    def details = entries.flat_map(&:details)

    # A single line suitable for an exception message.
    #
    # @return [String]
    def summary
      lead = detail || title || entries.first&.description
      parts = [lead, *details.reject { |d| d == lead }].compact
      body = parts.empty? ? "HTTP #{status}" : parts.join(" ")
      code ? "[#{code}] #{body}" : body
    end
  end
end
