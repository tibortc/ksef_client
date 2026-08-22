# frozen_string_literal: true

require_relative "../../tasks/ksef_bootstrap"

# Live integration against the KSeF TEST environment (DESIGN.md §9, docs/REFERENCE.md §6a.4).
#
# Opt-in twice over: tagged `:integration`, and excluded unless `KSEF_INTEGRATION=1`. It is
# nightly CI's job, never a per-PR one — it reaches the network and consumes shared
# TEST-environment state.
#
# **This suite provisions a fresh test person on each run** rather than reusing the identity
# `KSEF_TEST_NIP` refers to. That is deliberate: authenticating as an existing context by
# XAdES needs a certificate carrying the PESEL that holds the permissions, and the PESEL is
# not among the stored secrets. Self-provisioning keeps the suite self-contained at the cost
# of one test person per run, which is what the TEST environment exists for.
RSpec.describe "authentication against TEST", :integration do
  let(:configuration) { Ksef::Configuration.new(env: environment) }
  let(:connection) { Ksef::HTTP::Connection.build(configuration) }
  let(:client) { Ksef::Auth::Client.new(connection) }

  # Never PROD, from any code path. The suite-wide guard in spec_helper aborts on
  # `KSEF_ENV=prod`; this refuses anything that is not explicitly TEST.
  let(:environment) do
    env = (ENV["KSEF_ENV"] || "test").to_sym
    raise "Integration specs run against TEST only, got #{env}" unless env == :test

    env
  end

  describe "POST /auth/challenge" do
    subject(:challenge) { client.challenge }

    # Asserts §4.1's format claim against reality rather than against the XSD facet.
    it "returns a challenge in the documented 36-character form" do
      expect(challenge.challenge).to match(Ksef::Auth::TokenRequest::CHALLENGE_FORMAT)
    end

    it "reports the timestamp both ways, since the token flow needs milliseconds" do
      expect(challenge.timestamp).to be_a(Time)
      expect(challenge.timestamp_ms).to be_a(Integer)
    end

    # §4 records that the API pins the session to the IP it observed. Worth knowing the
    # field is really populated, since the ip-not-allowed failure depends on it.
    it "echoes the client IP it observed" do
      expect(challenge.client_ip).to match(/\A[\d.]+\z|:/)
    end

    it "is not yet expired when freshly issued" do
      expect(challenge).not_to be_expired
    end
  end

  # The assertion that matters: that the signature this gem builds is accepted by KSeF, not
  # merely self-consistent. Everything offline can prove is that our own arithmetic agrees
  # with itself.
  describe "the full XAdES flow" do
    subject(:tokens) { authenticate }

    let(:identifiers) do
      { nip: KsefBootstrap::Identifiers.nip, pesel: KsefBootstrap::Identifiers.pesel }
    end

    def provision
      connection.post("testdata/person") do |request|
        request.body = {
          nip: identifiers.fetch(:nip), pesel: identifiers.fetch(:pesel),
          isBailiff: false, isDeceased: false, description: "ksef_client nightly integration"
        }
      end
    end

    def signed_request
      certificate, key = KsefBootstrap::Certificate.personal(pesel: identifiers.fetch(:pesel))
      request = Ksef::Auth::TokenRequest.new(
        challenge: client.challenge.to_s, context_type: :nip, context_value: identifiers.fetch(:nip)
      )
      Ksef::Auth::Signer.new(certificate: certificate, key: key).sign(request)
    end

    # Provision, sign, submit, poll — everything up to but not including redemption, which
    # is single-use and so belongs to the caller.
    def submit_and_await
      provision
      initiated = client.submit_xades(signed_request)
      client.authenticate!(initiated.reference_number, token: initiated.authentication_token)
      initiated
    end

    def authenticate
      client.redeem(token: submit_and_await.authentication_token)
    end

    it "is accepted, and yields a usable token pair" do
      expect(tokens.access_token.token).to be_a(String)
      expect(tokens.refresh_token.token).to be_a(String)
      expect(tokens).not_to be_expired
    end

    it "issues an access token that expires sooner than the refresh token" do
      expect(tokens.access_token.valid_until).to be < tokens.refresh_token.valid_until
    end

    # §4.2: redemption is single-use, and a second attempt is a 400. Asserted because the
    # consequence of getting it wrong is a permanently unusable authentication.
    it "refuses a second redemption of the same authentication" do
      initiated = submit_and_await
      client.redeem(token: initiated.authentication_token)

      expect { client.redeem(token: initiated.authentication_token) }.to raise_error(Ksef::ApiError)
    end
  end
end
