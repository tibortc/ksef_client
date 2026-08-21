# frozen_string_literal: true

require "uri"

module Ksef
  # The three public KSeF API 2.0 environments.
  #
  # Every base URL here was read from that environment's *own* OpenAPI document
  # (`servers[0].url`, served at `https://<host>/docs/v2/openapi.json`) on 2026-08-21,
  # rather than inferred by analogy. See docs/REFERENCE.md §2. Do not edit a URL without
  # re-verifying it against that source and updating the ledger.
  #
  # Note the base URL already carries `/v2`; endpoint paths are appended bare. There is
  # no `/api` segment (docs/REFERENCE.md §7.2).
  module Environments
    Environment = Data.define(:name, :base_url, :supports_test_data) do
      # TEST alone exposes the `/testdata/*` helper API and `/collective-identifiers*`.
      # Code touching those paths must be guarded on this.
      def test_data_api? = supports_test_data

      def production? = name == :prod
    end

    TEST = Environment.new(
      name: :test,
      base_url: "https://api-test.ksef.mf.gov.pl/v2",
      supports_test_data: true
    )

    DEMO = Environment.new(
      name: :demo,
      base_url: "https://api-demo.ksef.mf.gov.pl/v2",
      supports_test_data: false
    )

    PROD = Environment.new(
      name: :prod,
      base_url: "https://api.ksef.mf.gov.pl/v2",
      supports_test_data: false
    )

    ALL = { test: TEST, demo: DEMO, prod: PROD }.freeze
    NAMES = ALL.keys.freeze

    class << self
      # @param env [Symbol, String, Environment]
      # @return [Environment]
      # @raise [Ksef::ConfigurationError] on an unknown environment
      def fetch(env)
        return env if env.is_a?(Environment)

        key = env.respond_to?(:to_sym) ? env.to_sym : nil
        ALL.fetch(key) do
          raise ConfigurationError,
                "Unknown KSeF environment #{env.inspect}. Known: #{NAMES.map(&:inspect).join(", ")}. " \
                "For a non-public deployment, pass Ksef::Environments.custom(base_url: ...)."
        end
      end

      # Escape hatch for deployments not covered by the three published environments
      # (DESIGN.md §6.1).
      #
      # @param base_url [String] must be HTTPS, and should include the `/v2` suffix
      # @return [Environment]
      def custom(base_url:, name: :custom, supports_test_data: false)
        uri = begin
          URI.parse(base_url)
        rescue URI::InvalidURIError => e
          raise ConfigurationError, "Invalid base_url #{base_url.inspect}: #{e.message}"
        end

        unless uri.is_a?(URI::HTTPS)
          raise ConfigurationError,
                "base_url must be HTTPS, got #{base_url.inspect}. TLS is not optional (DESIGN.md §4.5)."
        end

        Environment.new(
          name: name.to_sym,
          base_url: base_url.chomp("/"),
          supports_test_data: supports_test_data
        )
      end
    end
  end
end
