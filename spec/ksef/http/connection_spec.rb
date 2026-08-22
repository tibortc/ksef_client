# frozen_string_literal: true

RSpec.describe Ksef::HTTP::Connection do
  subject(:connection) { described_class.build(config) }

  let(:config) { Ksef::Configuration.new(env: :test) }
  let(:base) { "https://api-test.ksef.mf.gov.pl/v2" }

  describe "connection shape" do
    # Asserted behaviourally rather than by reading url_prefix: what matters is that a
    # relative path lands under /v2, since the base URL carries the version segment and
    # there is no /api prefix (docs/REFERENCE.md §7.2).
    it "resolves a relative path under the versioned base URL" do
      stub = stub_request(:post, "#{base}/auth/challenge").to_return(
        status: 200, body: "{}", headers: { "Content-Type" => "application/json" }
      )

      connection.post("auth/challenge", {})

      expect(stub).to have_been_requested
    end

    it "applies the configured timeouts" do
      expect(connection.options.open_timeout).to eq(10)
      expect(connection.options.timeout).to eq(60)
    end

    it "sends the gem's user agent" do
      expect(connection.headers["User-Agent"]).to eq(config.user_agent)
    end

    # Without this the API returns the deprecated error envelopes, losing traceId, the
    # structured error codes on 400 and reasonCode on 403 (docs/REFERENCE.md §5.1).
    it "opts into RFC7807 error bodies" do
      expect(connection.headers["X-Error-Format"]).to eq("problem-details")
    end

    # DESIGN.md §4.5: no code path may weaken TLS.
    it "verifies TLS and floors the version at 1.2" do
      expect(connection.ssl.verify).to be(true)
      expect(connection.ssl.min_version).to eq(:TLS1_2)
    end

    it "uses the configured adapter" do
      expect(connection.builder.adapter).to eq(Faraday::Adapter::NetHttp)
    end

    # Proxy support is configurable but was entirely unexercised — a corporate-proxy user
    # would have been the first to find out whether it worked.
    it "applies a configured proxy" do
      proxied = described_class.build(Ksef::Configuration.new(env: :test, proxy: "http://proxy.example:3128"))
      expect(proxied.proxy.uri.to_s).to eq("http://proxy.example:3128")
    end

    it "leaves the proxy unset when none is configured" do
      expect(connection.proxy).to be_nil
    end

    # Faraday runs on_complete callbacks innermost-first, so the JSON parser has to be
    # registered after the error handler for the handler to see a decoded body. This is
    # easy to break by "tidying" the middleware order, so it is pinned here.
    it "registers the JSON response parser inside the error handler" do
      handlers = connection.builder.handlers
      expect(handlers.index(Ksef::HTTP::ErrorHandler))
        .to be < handlers.index(Faraday::Response::Json)
    end
  end

  describe "successful responses" do
    it "decodes a JSON body" do
      stub_request(:get, "#{base}/rate-limits")
        .to_return(status: 200, body: '{"limit":60}', headers: { "Content-Type" => "application/json" })

      expect(connection.get("rate-limits").body).to eq("limit" => 60)
    end

    it "logs an X-System-Warning when one is present" do
      logger = double("Logger", debug: nil, info: nil, warn: nil, error: nil) # rubocop:disable RSpec/VerifiedDoubles
      allow(logger).to receive(:warn)

      stub_request(:get, "#{base}/rate-limits").to_return(
        status: 200, body: "{}",
        headers: { "Content-Type" => "application/json", "X-System-Warning" => "Kontrakt zmieni się 2026-09-01" }
      )

      described_class.build(Ksef::Configuration.new(env: :test, logger: logger)).get("rate-limits")

      expect(logger).to have_received(:warn).with(/X-System-Warning: Kontrakt zmieni się 2026-09-01/)
    end

    it "does not blow up when a warning arrives with no logger configured" do
      stub_request(:get, "#{base}/rate-limits").to_return(
        status: 200, body: "{}",
        headers: { "Content-Type" => "application/json", "X-System-Warning" => "note" }
      )

      expect { connection.get("rate-limits") }.not_to raise_error
    end
  end

  describe "error mapping" do
    def stub_error(status, body, content_type: "application/problem+json", headers: {})
      stub_request(:get, "#{base}/sessions")
        .to_return(status: status, body: JSON.dump(body),
                   headers: { "Content-Type" => content_type }.merge(headers))
    end

    it "raises ApiError on 400 with the parsed body available" do
      stub_error(400, { "title" => "Bad Request", "status" => 400, "detail" => "Nieprawidłowe.",
                        "errors" => [{ "code" => 21_405, "description" => "Błąd walidacji." }],
                        "traceId" => "trace-1" })

      expect { connection.get("sessions") }.to raise_error(Ksef::ApiError) do |error|
        expect(error).to have_attributes(status: 400, code: 21_405, trace_id: "trace-1")
        expect(error.raw).to be_a(Hash)
        expect(error.message).to include("traceId: trace-1")
      end
    end

    it "raises AuthenticationError on 401" do
      stub_error(401, { "title" => "Unauthorized", "status" => 401, "detail" => "Wymagane uwierzytelnienie." })

      expect { connection.get("sessions") }.to raise_error(Ksef::AuthenticationError, /401/)
    end

    it "raises AuthorizationError on 403, preserving the reason code" do
      stub_error(403, { "title" => "Forbidden", "status" => 403, "detail" => "Brak uprawnień.",
                        "reasonCode" => "missing-permissions",
                        "security" => { "requiredAnyOfPermissions" => ["InvoiceWrite"] } })

      expect { connection.get("sessions") }.to raise_error(Ksef::AuthorizationError) do |error|
        expect(error.reason_code).to eq("missing-permissions")
        expect(error.security["requiredAnyOfPermissions"]).to eq(["InvoiceWrite"])
      end
    end

    it "raises ResourceGoneError on 410" do
      stub_error(410, { "title" => "Gone", "status" => 410, "detail" => "Zasób wygasł." })

      expect { connection.get("sessions") }.to raise_error(Ksef::ResourceGoneError)
    end

    it "raises ServerError on 5xx even though the contract never declares it" do
      stub_request(:get, "#{base}/sessions").to_return(status: 503, body: "upstream down")

      expect { connection.get("sessions") }.to raise_error(Ksef::ServerError) do |error|
        expect(error.status).to eq(503)
        expect(error.raw).to eq("upstream down")
      end
    end

    # A 4xx the contract never declares — an intermediary or WAF can produce one. It must
    # surface as a plain ApiError rather than being misfiled as a server fault.
    it "raises ApiError for an undeclared 4xx status" do
      stub_request(:get, "#{base}/sessions").to_return(status: 404, body: "nope")

      expect { connection.get("sessions") }.to raise_error(Ksef::ApiError) do |error|
        expect(error).not_to be_a(Ksef::ServerError)
        expect(error.status).to eq(404)
      end
    end

    describe "429" do
      it "raises RateLimitedError carrying Retry-After in seconds" do
        stub_error(429, { "title" => "Too Many Requests", "status" => 429, "detail" => "Limit." },
                   headers: { "Retry-After" => "30" })

        expect { connection.get("sessions") }.to raise_error(Ksef::RateLimitedError) do |error|
          expect(error.retry_after).to eq(30)
        end
      end

      it "handles the HTTP-date form of Retry-After defensively" do
        stub_error(429, { "title" => "Too Many Requests", "status" => 429, "detail" => "Limit." },
                   headers: { "Retry-After" => (Time.now + 45).httpdate })

        expect { connection.get("sessions") }.to raise_error(Ksef::RateLimitedError) do |error|
          expect(error.retry_after).to be_within(2).of(45)
        end
      end

      # A date already in the past means "retry now", not "wait a negative time".
      it "clamps a past HTTP-date Retry-After to zero" do
        stub_error(429, { "title" => "Too Many Requests", "status" => 429, "detail" => "Limit." },
                   headers: { "Retry-After" => (Time.now - 120).httpdate })

        expect { connection.get("sessions") }.to raise_error(Ksef::RateLimitedError) do |error|
          expect(error.retry_after).to eq(0)
        end
      end

      it "leaves retry_after nil for an unparseable Retry-After" do
        stub_error(429, { "title" => "Too Many Requests", "status" => 429, "detail" => "Limit." },
                   headers: { "Retry-After" => "soon-ish" })

        expect { connection.get("sessions") }.to raise_error(Ksef::RateLimitedError) do |error|
          expect(error.retry_after).to be_nil
        end
      end

      it "leaves retry_after nil when the header is absent" do
        stub_error(429, { "title" => "Too Many Requests", "status" => 429, "detail" => "Limit." })

        expect { connection.get("sessions") }.to raise_error(Ksef::RateLimitedError) do |error|
          expect(error.retry_after).to be_nil
        end
      end

      it "parses the deprecated application/json 429 envelope" do
        stub_error(429,
                   { "status" => { "code" => 429, "description" => "Too Many Requests",
                                   "details" => ["Przekroczono limit 20 żądań na minutę."] } },
                   content_type: "application/json", headers: { "Retry-After" => "30" })

        expect { connection.get("sessions") }.to raise_error(Ksef::RateLimitedError) do |error|
          expect(error.retry_after).to eq(30)
          expect(error.details).to include("Przekroczono limit 20 żądań na minutę.")
        end
      end
    end
  end

  describe "transport failures" do
    # The net_http adapter reports an open timeout as Faraday::ConnectionFailed. It must
    # still surface as a timeout: after a POST, "timed out" and "refused" have very
    # different implications for whether the invoice reached KSeF.
    it "classifies an open timeout as a timeout, not a connection failure" do
      stub_request(:get, "#{base}/sessions").to_timeout

      expect { connection.get("sessions") }.to raise_error(Ksef::TimeoutError, /timed out/)
    end

    it "classifies a read timeout as a timeout" do
      stub_request(:get, "#{base}/sessions")
        .to_raise(Faraday::ConnectionFailed.new(Net::ReadTimeout.new))

      expect { connection.get("sessions") }.to raise_error(Ksef::TimeoutError)
    end

    it "wraps a genuine connection failure" do
      stub_request(:get, "#{base}/sessions").to_raise(Faraday::ConnectionFailed.new("econnrefused"))

      expect { connection.get("sessions") }.to raise_error(Ksef::ConnectionError, /Could not connect/)
    end

    it "wraps a TLS failure" do
      stub_request(:get, "#{base}/sessions").to_raise(Faraday::SSLError.new("cert verify failed"))

      expect { connection.get("sessions") }.to raise_error(Ksef::ConnectionError, /TLS failure/)
    end
  end
end
