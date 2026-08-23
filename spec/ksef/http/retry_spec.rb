# frozen_string_literal: true

RSpec.describe Ksef::HTTP::Retry do
  let(:base) { "https://api-test.ksef.mf.gov.pl/v2" }
  let(:slept) { [] }
  let(:policy) { Ksef::RetryPolicy.default }

  # A connection with the real stack, but a sleeper that records instead of waiting.
  def connection(policy_override = policy)
    config = Ksef::Configuration.new(env: :test, retry: policy_override)
    Faraday.new(url: config.base_url, headers: { "Accept" => "application/json" }) do |f|
      f.request :json
      f.use described_class, policy: config.retry_policy, sleeper: ->(s) { slept << s }
      f.use Ksef::HTTP::ErrorHandler
      f.response :json, content_type: /\bjson\b/
      f.adapter :net_http
    end
  end

  def json(body, status:, headers: {})
    { status: status, body: JSON.dump(body),
      headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  # The rule this middleware exists to respect. A duplicate invoice in KSeF is a real tax
  # problem, so a POST whose response never arrived must reach the caller.
  describe "non-idempotent requests" do
    it "never retries a POST, even on 429" do
      stub_request(:post, "#{base}/sessions/online")
        .to_return(json({ "status" => 429 }, status: 429, headers: { "Retry-After" => "1" }))

      expect { connection.post("sessions/online") }.to raise_error(Ksef::RateLimitedError)
      expect(a_request(:post, "#{base}/sessions/online")).to have_been_made.once
      expect(slept).to be_empty
    end

    it "never retries a POST on 503" do
      stub_request(:post, "#{base}/sessions/online").to_return(status: 503, body: "down")

      expect { connection.post("sessions/online") }.to raise_error(Ksef::ServerError)
      expect(a_request(:post, "#{base}/sessions/online")).to have_been_made.once
    end

    it "never retries a POST that timed out — it may have been processed" do
      stub_request(:post, "#{base}/sessions/online").to_timeout

      expect { connection.post("sessions/online") }.to raise_error(Ksef::TimeoutError)
      expect(a_request(:post, "#{base}/sessions/online")).to have_been_made.once
    end
  end

  describe "idempotent requests" do
    it "retries a GET on 429 and returns the eventual success" do
      stub_request(:get, "#{base}/rate-limits").to_return(
        json({ "status" => 429 }, status: 429, headers: { "Retry-After" => "2" }),
        json({ "ok" => true }, status: 200)
      )
      response = connection.get("rate-limits")

      expect(response.body).to eq("ok" => true)
      expect(a_request(:get, "#{base}/rate-limits")).to have_been_made.twice
    end

    it "retries a GET on 5xx" do
      stub_request(:get, "#{base}/rate-limits")
        .to_return({ status: 502, body: "bad gateway" }, json({ "ok" => true }, status: 200))

      expect(connection.get("rate-limits").body).to eq("ok" => true)
    end

    it "retries a transport failure, where there is no status to read" do
      stub_request(:get, "#{base}/rate-limits").to_timeout.then.to_return(json({ "ok" => true }, status: 200))

      expect(connection.get("rate-limits").body).to eq("ok" => true)
      expect(slept).to eq([1.0])
    end

    it "gives up after max_attempts and raises the last error" do
      stub_request(:get, "#{base}/rate-limits").to_return(status: 503, body: "down")

      expect { connection.get("rate-limits") }.to raise_error(Ksef::ServerError)
      expect(a_request(:get, "#{base}/rate-limits")).to have_been_made.times(3)
      expect(slept).to eq([1.0, 2.0])
    end

    it "does not retry a 400, 401, 403 or 410 — those are definite answers" do
      [400, 401, 403, 410].each do |status|
        WebMock.reset!
        stub_request(:get, "#{base}/rate-limits").to_return(json({ "status" => status }, status: status))

        expect { connection.get("rate-limits") }.to raise_error(Ksef::Error)
        expect(a_request(:get, "#{base}/rate-limits")).to have_been_made.once
      end
    end
  end

  describe "Retry-After" do
    # Honoured unclamped: waiting less than the server asked lengthens the block, and KSeF
    # treats repeat offences as an abuse pattern (docs/REFERENCE.md §6).
    it "waits exactly what the server asked, even beyond max_interval" do
      stub_request(:get, "#{base}/rate-limits").to_return(
        json({ "status" => 429 }, status: 429, headers: { "Retry-After" => "45" }),
        json({ "ok" => true }, status: 200)
      )
      connection.get("rate-limits")

      expect(slept).to eq([45.0])
      expect(45).to be > Ksef::RetryPolicy.default.max_interval
    end

    # If we are not prepared to wait the full period we must not retry at all — retrying
    # sooner is worse than not retrying.
    it "declines the retry when the wait exceeds max_retry_after" do
      stub_request(:get, "#{base}/rate-limits")
        .to_return(json({ "status" => 429 }, status: 429, headers: { "Retry-After" => "600" }))

      expect { connection.get("rate-limits") }.to raise_error(Ksef::RateLimitedError)
      expect(a_request(:get, "#{base}/rate-limits")).to have_been_made.once
      expect(slept).to be_empty
    end
  end

  describe "the request body across attempts" do
    # An adapter may consume the body; without restoring it, attempt two would send an empty
    # one and the retry would silently change the request.
    # A GET with a body is unusual but legal, and it is the only way to exercise this on a
    # method the policy will actually retry.
    it "sends the identical body on every attempt" do
      stub_request(:get, "#{base}/invoices/query/metadata")
        .to_return({ status: 503, body: "x" }, { status: 200, body: "{}" })
      connection.get("invoices/query/metadata") { |request| request.body = '{"page":1}' }

      expect(a_request(:get, "#{base}/invoices/query/metadata").with(body: '{"page":1}'))
        .to have_been_made.twice
    end
  end

  describe "disabling it" do
    it "makes no second attempt when the policy allows one" do
      stub_request(:get, "#{base}/rate-limits").to_return(status: 503, body: "down")

      expect { connection(Ksef::RetryPolicy.none).get("rate-limits") }
        .to raise_error(Ksef::ServerError)
      expect(a_request(:get, "#{base}/rate-limits")).to have_been_made.once
    end
  end

  describe "logging" do
    it "reports each retry, since it hides latency from the caller" do
      logged = []
      logger = Object.new
      logger.define_singleton_method(:info) { |message| logged << message }
      conn = Faraday.new(url: base) do |f|
        f.use described_class, policy: policy, sleeper: ->(_) {}, logger: logger
        f.use Ksef::HTTP::ErrorHandler
        f.adapter :net_http
      end
      stub_request(:get, "#{base}/rate-limits")
        .to_return({ status: 503, body: "x" }, { status: 200, body: "ok" })
      conn.get("rate-limits")

      expect(logged.first).to include("retrying GET", "ServerError", "attempt 2")
    end

    it "stays silent when no logger is configured" do
      stub_request(:get, "#{base}/rate-limits").to_return({ status: 503, body: "x" }, { status: 200, body: "{}" })

      expect { connection.get("rate-limits") }.not_to raise_error
    end
  end
end
