# frozen_string_literal: true

module Ksef
  module Auth
    # The optional `AuthorizationPolicy` of an {TokenRequest} — a whitelist restricting
    # which client IPs may use the resulting `accessToken`.
    #
    # Its own class rather than a Hash inside {TokenRequest} because the schema treats it
    # as a distinct structure with its own rules: three list kinds, each capped at ten
    # entries, in a fixed order, wrapped in an `AllowedIps` element that is mandatory once
    # the policy is present (docs/REFERENCE.md §4.1).
    #
    # The IP values are deliberately **not** pattern-checked here. v2.1's patterns are
    # correct and the schema will catch a malformed address, whereas v2.0's are broken
    # outright (§14.4) — duplicating either in Ruby would mean maintaining a second,
    # divergent source of truth for no gain.
    class AuthorizationPolicy
      MAX_IPS = 10

      # Ordered as the schema sequences them; the caller's Hash order is irrelevant.
      IP_ELEMENTS = { addresses: "Ip4Address", ranges: "Ip4Range", masks: "Ip4Mask" }.freeze

      attr_reader :addresses, :ranges, :masks

      # @return [AuthorizationPolicy, nil] passes `nil` and an existing policy through
      # @raise [Ksef::ValidationError] on an unknown key
      def self.coerce(value)
        return value if value.nil? || value.is_a?(self)

        unknown = value.keys - IP_ELEMENTS.keys
        unless unknown.empty?
          raise ValidationError,
                "Unknown allowed_ips key(s) #{unknown.map(&:inspect).join(", ")}. " \
                "Permitted: #{IP_ELEMENTS.keys.map(&:inspect).join(", ")}."
        end

        new(**value)
      end

      def initialize(addresses: [], ranges: [], masks: [])
        @addresses = Array(addresses).freeze
        @ranges = Array(ranges).freeze
        @masks = Array(masks).freeze
        validate!
        freeze
      end

      # @return [Array<Array(String, String)>] `[element name, value]` pairs in schema order
      def entries
        IP_ELEMENTS.flat_map { |key, name| public_send(key).map { |value| [name, value] } }
      end

      def empty? = addresses.empty? && ranges.empty? && masks.empty?

      private

      def validate!
        # AllowedIps is mandatory inside AuthorizationPolicy, so an empty policy cannot be
        # made schema-valid. Saying so beats emitting a document KSeF will reject.
        raise ValidationError, "allowed_ips was given but lists no addresses" if empty?

        IP_ELEMENTS.each_key { |key| check_count(key, public_send(key)) }
      end

      def check_count(key, list)
        return if list.size <= MAX_IPS

        raise ValidationError,
              "allowed_ips[#{key.inspect}] has #{list.size} entries; the schema permits #{MAX_IPS}"
      end
    end
  end
end
