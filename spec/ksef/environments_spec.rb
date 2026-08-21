# frozen_string_literal: true

RSpec.describe Ksef::Environments do
  # These URLs are the contract with the Ministry's infrastructure. They were verified
  # against each environment's own OpenAPI document (docs/REFERENCE.md §2); a change here
  # is a change to a verified fact and must go through the ledger.
  describe "verified base URLs" do
    it "points TEST at the RC environment" do
      expect(described_class::TEST.base_url).to eq("https://api-test.ksef.mf.gov.pl/v2")
    end

    it "points DEMO at the pre-production environment" do
      expect(described_class::DEMO.base_url).to eq("https://api-demo.ksef.mf.gov.pl/v2")
    end

    it "points PROD at the production environment" do
      expect(described_class::PROD.base_url).to eq("https://api.ksef.mf.gov.pl/v2")
    end

    it "includes the /v2 version segment and no /api segment" do
      described_class::ALL.each_value do |env|
        expect(env.base_url).to end_with("/v2")
        expect(env.base_url).not_to include("/api/")
      end
    end

    it "uses HTTPS everywhere" do
      expect(described_class::ALL.values.map(&:base_url)).to all(start_with("https://"))
    end
  end

  describe "capabilities" do
    it "exposes the test-data helper API on TEST only" do
      expect(described_class::TEST.test_data_api?).to be(true)
      expect(described_class::DEMO.test_data_api?).to be(false)
      expect(described_class::PROD.test_data_api?).to be(false)
    end

    it "identifies production" do
      expect(described_class::PROD.production?).to be(true)
      expect(described_class::TEST.production?).to be(false)
    end
  end

  describe ".fetch" do
    it "resolves a symbol" do
      expect(described_class.fetch(:demo)).to eq(described_class::DEMO)
    end

    it "resolves a string" do
      expect(described_class.fetch("prod")).to eq(described_class::PROD)
    end

    it "passes an Environment through unchanged" do
      custom = described_class.custom(base_url: "https://ksef.example.test/v2")
      expect(described_class.fetch(custom)).to equal(custom)
    end

    it "raises a helpful error for an unknown name" do
      expect { described_class.fetch(:staging) }
        .to raise_error(Ksef::ConfigurationError, /Unknown KSeF environment :staging.*:test, :demo, :prod/m)
    end

    it "raises for a value that cannot be a name" do
      expect { described_class.fetch(42) }.to raise_error(Ksef::ConfigurationError)
    end
  end

  describe ".custom" do
    it "builds an environment from an HTTPS URL" do
      env = described_class.custom(base_url: "https://ksef.example.test/v2")
      expect(env.base_url).to eq("https://ksef.example.test/v2")
      expect(env.name).to eq(:custom)
      expect(env.test_data_api?).to be(false)
    end

    it "strips a trailing slash" do
      expect(described_class.custom(base_url: "https://ksef.example.test/v2/").base_url)
        .to eq("https://ksef.example.test/v2")
    end

    it "refuses plaintext HTTP" do
      expect { described_class.custom(base_url: "http://ksef.example.test/v2") }
        .to raise_error(Ksef::ConfigurationError, /must be HTTPS/)
    end

    it "refuses a malformed URL" do
      expect { described_class.custom(base_url: "https://exa mple.test") }
        .to raise_error(Ksef::ConfigurationError, /Invalid base_url/)
    end
  end
end
