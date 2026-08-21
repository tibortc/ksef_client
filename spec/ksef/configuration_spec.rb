# frozen_string_literal: true

RSpec.describe Ksef::Configuration do
  # A bare double, not instance_double(Logger): the gem duck-types the logger precisely
  # so it never has to require the `logger` bundled gem (DESIGN.md §4.3).
  let(:logger) { double("Logger", debug: nil, info: nil, warn: nil, error: nil) } # rubocop:disable RSpec/VerifiedDoubles

  describe "defaults" do
    subject(:config) { described_class.new }

    it "defaults to the TEST environment" do
      expect(config.environment).to eq(Ksef::Environments::TEST)
      expect(config.base_url).to eq("https://api-test.ksef.mf.gov.pl/v2")
    end

    it "defaults to the net_http adapter" do
      expect(config.adapter).to eq(:net_http)
    end

    it "applies the documented default timeouts" do
      expect(config.open_timeout).to eq(10)
      expect(config.read_timeout).to eq(60)
    end

    it "defaults to the standard retry policy" do
      expect(config.retry_policy).to eq(Ksef::RetryPolicy.default)
    end

    it "identifies the gem and Ruby version in the user agent" do
      expect(config.user_agent).to eq("ksef_client/#{Ksef::VERSION} (Ruby #{RUBY_VERSION})")
    end
  end

  # DESIGN.md §5.2: one client shared across threads, so config must be immutable.
  describe "immutability" do
    it "freezes itself at construction" do
      expect(described_class.new).to be_frozen
    end

    it "freezes the timeout hash" do
      expect(described_class.new.timeout).to be_frozen
    end
  end

  # DESIGN.md §4.5: credentials must never reach a log or a backtrace.
  describe "#inspect" do
    let(:secret) { "super-secret-ksef-token" }
    let(:config) { described_class.new(auth: secret) }

    it "redacts the credential" do
      expect(config.inspect).to include("[REDACTED]")
      expect(config.inspect).not_to include(secret)
    end

    it "redacts via to_s as well" do
      expect(config.to_s).not_to include(secret)
    end

    it "reports a nil credential honestly" do
      expect(described_class.new.inspect).to include("auth=nil")
    end

    it "still shows the environment, so the output stays useful" do
      expect(config.inspect).to include(":test", "https://api-test.ksef.mf.gov.pl/v2")
    end
  end

  describe "retry option" do
    # DESIGN.md §6.1 spells the option `retry:`, which cannot be a readable method
    # parameter name in Ruby, so it arrives through **options.
    it "accepts the documented retry: keyword" do
      policy = Ksef::RetryPolicy.none
      expect(described_class.new(retry: policy).retry_policy).to eq(policy)
    end

    it "also accepts retry_policy: as an alias" do
      policy = Ksef::RetryPolicy.none
      expect(described_class.new(retry_policy: policy).retry_policy).to eq(policy)
    end

    it "rejects an object that is not a retry policy" do
      expect { described_class.new(retry: "aggressive") }
        .to raise_error(Ksef::ConfigurationError, /must respond to #retryable\?/)
    end
  end

  describe "timeouts" do
    it "accepts a scalar and applies it to both phases" do
      config = described_class.new(timeout: 5)
      expect(config.open_timeout).to eq(5)
      expect(config.read_timeout).to eq(5)
    end

    it "accepts a partial hash and keeps the other default" do
      config = described_class.new(timeout: { read: 120 })
      expect(config.read_timeout).to eq(120)
      expect(config.open_timeout).to eq(10)
    end

    it "rejects an unknown key rather than silently ignoring it" do
      expect { described_class.new(timeout: { write: 5 }) }
        .to raise_error(Ksef::ConfigurationError, /Unknown timeout key :write/)
    end

    it "rejects a non-positive value" do
      expect { described_class.new(timeout: { read: 0 }) }
        .to raise_error(Ksef::ConfigurationError, /positive number/)
    end

    it "rejects a nonsense type" do
      expect { described_class.new(timeout: "fast") }
        .to raise_error(Ksef::ConfigurationError, /must be a Numeric or a Hash/)
    end
  end

  describe "logger" do
    it "accepts any object quacking like a logger" do
      expect(described_class.new(logger: logger).logger).to eq(logger)
    end

    it "accepts nil" do
      expect(described_class.new(logger: nil).logger).to be_nil
    end

    it "names the methods a rejected logger is missing" do
      expect { described_class.new(logger: Object.new) }
        .to raise_error(Ksef::ConfigurationError, /:debug, :info, :warn, :error/)
    end
  end

  describe "unknown options" do
    it "rejects a typo rather than ignoring it" do
      expect { described_class.new(timeoout: 5) }
        .to raise_error(Ksef::ConfigurationError, /Unknown configuration option\(s\): :timeoout/)
    end
  end

  describe "environment plumbing" do
    it "accepts a custom environment" do
      env = Ksef::Environments.custom(base_url: "https://ksef.example.test/v2")
      expect(described_class.new(env: env).base_url).to eq("https://ksef.example.test/v2")
    end

    it "flags production" do
      expect(described_class.new(env: :prod).production?).to be(true)
    end
  end
end
