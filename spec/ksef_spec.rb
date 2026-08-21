# frozen_string_literal: true

RSpec.describe Ksef do
  it "has a SemVer version" do
    expect(Ksef::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  # DESIGN.md §5.3: the gem is `ksef_client`, the namespace is `Ksef`.
  it "defines the Ksef namespace when the gem name is required" do
    expect(require("ksef_client")).to be(false) # already loaded by spec_helper
    expect(Object.const_defined?(:Ksef)).to be(true)
  end

  it "exposes its Zeitwerk loader for forking servers" do
    expect(described_class.loader).to be_a(Zeitwerk::Loader)
  end

  it "eager loads without a missing-constant error" do
    expect { described_class.loader.eager_load }.not_to raise_error
  end

  describe "error hierarchy" do
    it "roots everything at Ksef::Error" do
      [
        Ksef::ConfigurationError, Ksef::AuthenticationError, Ksef::ValidationError,
        Ksef::ApiError, Ksef::TimeoutError, Ksef::ConnectionError
      ].each { |klass| expect(klass.ancestors).to include(Ksef::Error) }
    end

    it "roots response errors at Ksef::ApiError" do
      [
        Ksef::InvoiceRejectedError, Ksef::SessionError, Ksef::AuthorizationError,
        Ksef::ResourceGoneError, Ksef::RateLimitedError, Ksef::ServerError
      ].each { |klass| expect(klass.ancestors).to include(Ksef::ApiError) }
    end

    it "makes everything rescuable as StandardError" do
      expect(Ksef::Error.ancestors).to include(StandardError)
    end

    it "leaves #problem nil for locally raised errors" do
      expect(Ksef::ConfigurationError.new("bad").problem).to be_nil
    end

    it "returns empty details rather than nil when there is no problem body" do
      expect(Ksef::ApiError.new("boom").details).to eq([])
    end
  end
end
