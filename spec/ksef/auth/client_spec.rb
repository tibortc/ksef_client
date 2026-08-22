# frozen_string_literal: true

RSpec.describe Ksef::Auth::Client do
  let(:base) { "https://api-test.ksef.mf.gov.pl/v2" }
  let(:connection) { Ksef::HTTP::Connection.build(Ksef::Configuration.new(env: :test)) }
  let(:client) { described_class.new(connection) }

  def json(body, status: 200)
    { status: status, body: JSON.dump(body), headers: { "Content-Type" => "application/json" } }
  end

  def token_info(token = "jwt.value") = { "token" => token, "validUntil" => "2026-08-22T12:00:00Z" }

  def status_body(code, description = "x", **rest)
    { "status" => { "code" => code, "description" => description },
      "authenticationMethod" => "QualifiedSignature", "startDate" => "2026-08-22T10:00:00Z" }.merge(rest)
  end

  describe "#challenge" do
    it "parses the challenge, its timestamps and the observed client IP" do
      stub_request(:post, "#{base}/auth/challenge").to_return(
        json({ "challenge" => "20250604-CR-461EA5B000-537A6BA15D-D7", "timestamp" => "2026-08-22T10:00:00Z",
               "timestampMs" => 1_787_824_800_000, "clientIp" => "203.0.113.7" })
      )
      result = client.challenge

      expect(result.challenge).to eq("20250604-CR-461EA5B000-537A6BA15D-D7")
      expect(result.timestamp).to eq(Time.utc(2026, 8, 22, 10))
      expect(result.timestamp_ms).to eq(1_787_824_800_000)
      expect(result.client_ip).to eq("203.0.113.7")
    end

    # The contract marks this endpoint `security: []`.
    it "sends no Authorization header" do
      stub = stub_request(:post, "#{base}/auth/challenge").to_return(json({ "challenge" => "c" }))
      client.challenge

      expect(stub.with { |r| !r.headers.key?("Authorization") }).to have_been_made
    end

    it "knows when a challenge has aged out of its ten-minute window" do
      stub_request(:post, "#{base}/auth/challenge")
        .to_return(json({ "challenge" => "c", "timestamp" => "2026-08-22T10:00:00Z" }))
      result = client.challenge

      expect(result.expired?(Time.utc(2026, 8, 22, 10, 9, 59))).to be(false)
      expect(result.expired?(Time.utc(2026, 8, 22, 10, 10, 1))).to be(true)
    end
  end

  describe "#submit_xades" do
    it "posts the signed document as application/xml and returns the 202 body" do
      stub_request(:post, "#{base}/auth/xades-signature")
        .with(body: "<signed/>", headers: { "Content-Type" => "application/xml" })
        .to_return(json({ "referenceNumber" => "20260822-AU-1234567890-1234567890-AB",
                          "authenticationToken" => token_info("auth.jwt") }, status: 202))
      result = client.submit_xades("<signed/>")

      expect(result.reference_number).to eq("20260822-AU-1234567890-1234567890-AB")
      expect(result.token).to eq("auth.jwt")
    end

    it "omits the certificate-chain flag unless asked" do
      stub = stub_request(:post, "#{base}/auth/xades-signature").to_return(json({}, status: 202))
      client.submit_xades("<signed/>")

      expect(stub.with { |r| !r.uri.query.to_s.include?("verifyCertificateChain") }).to have_been_made
    end

    it "passes the flag through when given" do
      stub_request(:post, "#{base}/auth/xades-signature")
        .with(query: { "verifyCertificateChain" => "false" }).to_return(json({}, status: 202))

      expect { client.submit_xades("<signed/>", verify_certificate_chain: false) }.not_to raise_error
    end
  end

  describe "#status" do
    it "presents the authentication token as the bearer, not an access token" do
      stub_request(:get, "#{base}/auth/REF1")
        .with(headers: { "Authorization" => "Bearer auth.jwt" }).to_return(json(status_body(100, "W toku")))

      expect(client.status("REF1", token: "auth.jwt").in_progress?).to be(true)
    end

    it "accepts a TokenInfo without leaking [REDACTED] into the header" do
      stub_request(:get, "#{base}/auth/REF1")
        .with(headers: { "Authorization" => "Bearer auth.jwt" }).to_return(json(status_body(200)))

      expect(client.status("REF1", token: Ksef::Auth::TokenInfo.from(token_info("auth.jwt"))).success?).to be(true)
    end

    it "surfaces the server's own description and details" do
      stub_request(:get, "#{base}/auth/REF1").to_return(
        json({ "status" => { "code" => 415, "description" => "Brak uprawnień", "details" => ["nip 111"] } })
      )
      result = client.status("REF1", token: "t")

      expect(result.explain).to eq("Brak uprawnień")
      expect(result.details).to eq(["nip 111"])
      expect(result.terminal?).to be(true)
    end

    it "falls back to our own wording when the server sends none" do
      stub_request(:get, "#{base}/auth/REF1").to_return(json({ "status" => { "code" => 460 } }))

      expect(client.status("REF1", token: "t").explain).to include("certificate invalid, untrusted")
    end
  end

  describe "#wait_until_complete" do
    it "polls while in progress and stops at the first terminal status" do
      stub_request(:get, "#{base}/auth/REF1")
        .to_return(json(status_body(100)), json(status_body(100)), json(status_body(200, "OK")))
      slept = []
      result = client.wait_until_complete("REF1", token: "t", interval: 5, sleeper: ->(s) { slept << s })

      expect(result.success?).to be(true)
      expect(slept).to eq([5, 5])
    end

    it "yields each poll, so a caller can report progress on a long OCSP check" do
      stub_request(:get, "#{base}/auth/REF1").to_return(json(status_body(100)), json(status_body(200)))
      seen = []
      client.wait_until_complete("REF1", token: "t", sleeper: ->(_) {}) { |s| seen << s.code }

      expect(seen).to eq([100, 200])
    end

    it "does not sleep when the first poll is already terminal" do
      stub_request(:get, "#{base}/auth/REF1").to_return(json(status_body(200)))
      slept = []
      client.wait_until_complete("REF1", token: "t", sleeper: ->(s) { slept << s })

      expect(slept).to be_empty
    end

    # Treating an unknown code as retryable would poll a dead operation forever.
    it "treats an unrecognised code as terminal rather than polling forever" do
      stub_request(:get, "#{base}/auth/REF1").to_return(json(status_body(999)))

      expect(client.wait_until_complete("REF1", token: "t", sleeper: ->(_) {}).code).to eq(999)
    end
  end

  describe "#authenticate!" do
    it "returns the status on success" do
      stub_request(:get, "#{base}/auth/REF1").to_return(json(status_body(200)))

      expect(client.authenticate!("REF1", token: "t", sleeper: ->(_) {}).success?).to be(true)
    end

    it "raises with the code, the server's wording and its details" do
      stub_request(:get, "#{base}/auth/REF1").to_return(
        json({ "status" => { "code" => 460, "description" => "Certyfikat odwołany", "details" => ["serial 42"] } })
      )

      expect { client.authenticate!("REF1", token: "t", sleeper: ->(_) {}) }
        .to raise_error(Ksef::AuthenticationError, /status 460: Certyfikat odwołany \(serial 42\)/)
    end
  end

  describe "#redeem" do
    it "returns both tokens" do
      stub_request(:post, "#{base}/auth/token/redeem")
        .with(headers: { "Authorization" => "Bearer auth.jwt" })
        .to_return(json({ "accessToken" => token_info("access.jwt"), "refreshToken" => token_info("refresh.jwt") }))
      tokens = client.redeem(token: "auth.jwt")

      expect(tokens.access_token.token).to eq("access.jwt")
      expect(tokens.refresh_token.token).to eq("refresh.jwt")
    end

    # Single-use per §4.2, and a POST, so the retry policy already excludes it. A retry
    # would turn a transient blip into a permanently unusable authentication.
    it "surfaces the 400 a second redemption returns instead of retrying" do
      stub_request(:post, "#{base}/auth/token/redeem")
        .to_return(status: 400, body: JSON.dump("status" => { "code" => 400, "description" => "Already redeemed" }),
                   headers: { "Content-Type" => "application/json" })

      expect { client.redeem(token: "auth.jwt") }.to raise_error(Ksef::ApiError)
      expect(a_request(:post, "#{base}/auth/token/redeem")).to have_been_made.once
    end
  end

  describe "#refresh" do
    it "presents the refresh token and returns a new access token" do
      stub_request(:post, "#{base}/auth/token/refresh")
        .with(headers: { "Authorization" => "Bearer refresh.jwt" })
        .to_return(json({ "accessToken" => token_info("fresh.jwt") }))

      expect(client.refresh(refresh_token: "refresh.jwt").token).to eq("fresh.jwt")
    end
  end
end
