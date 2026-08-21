# frozen_string_literal: true

RSpec.describe Ksef::RetryPolicy do
  subject(:policy) { described_class.default }

  # The rule that matters most in this file is a tax rule, not a networking one:
  # a duplicate invoice in KSeF is a real problem, so submissions are never replayed
  # automatically (DESIGN.md §6.7).
  describe "#retryable?" do
    it "retries an idempotent GET on 429" do
      expect(policy.retryable?(method: :get, status: 429)).to be(true)
    end

    it "retries an idempotent GET on 5xx" do
      expect(policy.retryable?(method: :get, status: 503)).to be(true)
    end

    it "retries a HEAD" do
      expect(policy.retryable?(method: :head, status: 500)).to be(true)
    end

    it "never retries a POST, even on 429" do
      expect(policy.retryable?(method: :post, status: 429)).to be(false)
    end

    it "never retries a POST on 5xx — the invoice may already be recorded" do
      expect(policy.retryable?(method: :post, status: 500)).to be(false)
    end

    it "never retries a PUT or DELETE either" do
      expect(policy.retryable?(method: :put, status: 503)).to be(false)
      expect(policy.retryable?(method: :delete, status: 503)).to be(false)
    end

    it "accepts an uppercase verb" do
      expect(policy.retryable?(method: "GET", status: 429)).to be(true)
    end

    it "does not retry a 4xx that is not a rate limit" do
      expect(policy.retryable?(method: :get, status: 400)).to be(false)
      expect(policy.retryable?(method: :get, status: 403)).to be(false)
    end

    it "retries a transport failure on an idempotent request" do
      expect(policy.retryable?(method: :get, status: nil)).to be(true)
    end

    it "does not retry a transport failure on a POST" do
      expect(policy.retryable?(method: :post, status: nil)).to be(false)
    end

    it "stops at max_attempts" do
      expect(policy.retryable?(method: :get, status: 429, attempt: 3)).to be(false)
    end

    it "never retries when the policy is none" do
      expect(described_class.none.retryable?(method: :get, status: 429)).to be(false)
    end

    # Retrying sooner than the server demanded lengthens the block, so a wait we are not
    # willing to sit out means not retrying at all (docs/REFERENCE.md §6).
    it "declines to retry when Retry-After exceeds max_retry_after" do
      expect(policy.retryable?(method: :get, status: 429, retry_after: 3600)).to be(false)
    end

    it "still retries when Retry-After is within budget" do
      expect(policy.retryable?(method: :get, status: 429, retry_after: 30)).to be(true)
    end
  end

  describe "#interval_for" do
    it "backs off exponentially" do
      expect(policy.interval_for(attempt: 1)).to eq(1.0)
      expect(policy.interval_for(attempt: 2)).to eq(2.0)
      expect(policy.interval_for(attempt: 3)).to eq(4.0)
    end

    it "caps the computed backoff at max_interval" do
      expect(policy.interval_for(attempt: 99)).to eq(30.0)
    end

    it "prefers Retry-After over the computed backoff" do
      expect(policy.interval_for(attempt: 1, retry_after: 17)).to eq(17.0)
    end

    # Deliberately unclamped: waiting less than instructed makes the next block longer.
    it "does not clamp Retry-After to max_interval" do
      expect(policy.interval_for(attempt: 1, retry_after: 45)).to eq(45.0)
    end

    it "ignores Retry-After when the policy opts out" do
      opted_out = policy.with(respect_retry_after: false)
      expect(opted_out.interval_for(attempt: 1, retry_after: 45)).to eq(1.0)
    end
  end
end
