# frozen_string_literal: true

module Ksef
  # Immutable client configuration.
  #
  # Frozen at construction so a single {Ksef::Client} can be shared across threads
  # (DESIGN.md §5.2); all mutable per-operation state lives in session and flow objects.
  #
  # `#inspect` is redacted: credentials must never reach a log or an exception backtrace
  # (DESIGN.md §4.5).
  class Configuration
    DEFAULT_TIMEOUT = { open: 10, read: 60 }.freeze
    DEFAULT_ADAPTER = :net_http

    attr_reader :environment, :auth, :logger, :timeout, :retry_policy, :adapter, :proxy, :user_agent

    # @param env [Symbol, Ksef::Environments::Environment] `:test`, `:demo`, `:prod`, or
    #   the result of {Ksef::Environments.custom}
    # @param auth [Object, nil] a credential object, e.g. {Ksef::Auth::Token}
    # @param logger [Object, nil] any object responding to `#debug`/`#info`/`#warn`.
    #   Deliberately duck-typed — `logger` is a bundled gem as of Ruby 4.0 and this gem
    #   does not require it (DESIGN.md §4.3).
    # @param timeout [Hash] `{open:, read:}` in seconds
    # @param adapter [Symbol] Faraday adapter; kept swappable
    # @param options [Hash] accepts `retry:` (DESIGN.md §6.1) or `retry_policy:`,
    #   plus `proxy:` and `user_agent:`
    def initialize(env: :test, auth: nil, logger: nil, timeout: DEFAULT_TIMEOUT, adapter: DEFAULT_ADAPTER, **options)
      apply_options(options)

      @environment = Environments.fetch(env)
      @auth = auth
      @adapter = adapter
      @logger = validate_logger(logger)
      @timeout = normalize_timeout(timeout)

      validate_retry_policy!
      freeze
    end

    # @return [String] the environment base URL, already including `/v2`
    def base_url = environment.base_url

    def production? = environment.production?

    # @return [Integer] seconds
    def open_timeout = timeout.fetch(:open)

    # @return [Integer] seconds
    def read_timeout = timeout.fetch(:read)

    # Redacted — never expose `auth` (DESIGN.md §4.5).
    def inspect
      "#<#{self.class.name} env=#{environment.name.inspect} base_url=#{base_url.inspect} " \
        "auth=#{auth ? "[REDACTED]" : "nil"} adapter=#{adapter.inspect} timeout=#{timeout.inspect}>"
    end
    alias to_s inspect

    private

    # `retry` cannot be read as a method parameter name — it parses, but the body can only
    # reach it via binding tricks. DESIGN.md §6.1 spells the option `retry:`, so it is
    # accepted here through **options along with its clearer alias.
    def apply_options(options)
      options = options.dup
      @retry_policy = options.delete(:retry) || options.delete(:retry_policy) || RetryPolicy.default
      @proxy = options.delete(:proxy)
      @user_agent = options.delete(:user_agent) || default_user_agent

      return if options.empty?

      raise ConfigurationError, "Unknown configuration option(s): #{options.keys.map(&:inspect).join(", ")}"
    end

    def default_user_agent
      "ksef_client/#{Ksef::VERSION} (Ruby #{RUBY_VERSION})"
    end

    def validate_logger(logger)
      return if logger.nil?

      missing = %i[debug info warn error].reject { |m| logger.respond_to?(m) }
      unless missing.empty?
        raise ConfigurationError,
              "logger must respond to #{missing.map(&:inspect).join(", ")}; got #{logger.class}"
      end

      logger
    end

    def normalize_timeout(timeout)
      case timeout
      when Numeric then { open: timeout, read: timeout }.freeze
      when Hash then normalize_timeout_hash(timeout)
      else
        raise ConfigurationError, "timeout must be a Numeric or a Hash of {open:, read:}, got #{timeout.class}"
      end
    end

    def normalize_timeout_hash(timeout)
      normalized = DEFAULT_TIMEOUT.dup

      timeout.each do |key, value|
        sym = key.to_sym
        raise ConfigurationError, "Unknown timeout key #{key.inspect}; expected :open or :read" unless
          normalized.key?(sym)
        raise ConfigurationError, "timeout[#{sym.inspect}] must be a positive number, got #{value.inspect}" unless
          value.is_a?(Numeric) && value.positive?

        normalized[sym] = value
      end

      normalized.freeze
    end

    def validate_retry_policy!
      return if @retry_policy.respond_to?(:retryable?) && @retry_policy.respond_to?(:interval_for)

      raise ConfigurationError,
            "retry policy must respond to #retryable? and #interval_for; got #{@retry_policy.class}"
    end
  end
end
