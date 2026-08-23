# frozen_string_literal: true

require "openssl"

# Live integration for the crypto module against the KSeF TEST environment.
#
# Opt-in twice over, like `auth_flow_spec.rb`: tagged `:integration` and excluded unless
# `KSEF_INTEGRATION=1`.
#
# Two things here cannot be established offline, and both matter.
#
# **The identifier derivations of docs/REFERENCE.md §10.2** — `certificateId` as the
# SHA-256 of the DER certificate and `publicKeyId` as the SHA-256 of the DER
# `SubjectPublicKeyInfo`, both base64. The library never computes either: it sends back the
# `publicKeyId` the server gave it. So a unit test could only check the claim against a
# fixture built from the claim. Real certificates settle it.
#
# **That KSeF accepts a payload this gem encrypted.** The XAdES flow proved KSeF accepts a
# signature we produced (§6a.4); the token flow proves it can *decrypt* what we wrapped,
# because an access token is only issued if the RSA-OAEP ciphertext unwrapped to the right
# `token|timestampMs`. Every parameter of §10.1 is on the line in that one outcome.
RSpec.describe "cryptography against TEST", :integration do
  let(:configuration) { Ksef::Configuration.new(env: environment) }
  let(:connection) { Ksef::HTTP::Connection.build(configuration) }
  let(:keys) { Ksef::Crypto::PublicKeys.new(connection) }

  # Never PROD, from any code path.
  let(:environment) do
    env = (ENV["KSEF_ENV"] || "test").to_sym
    raise "Integration specs run against TEST only, got #{env}" unless env == :test

    env
  end

  def base64_sha256(bytes) = [OpenSSL::Digest::SHA256.digest(bytes)].pack("m0")

  describe "GET /security/public-key-certificates" do
    subject(:published) { keys.all }

    it "needs no credential, as the contract's missing `security` implies" do
      expect(published).not_to be_empty
    end

    it "publishes a key for each of the two usages the client selects between" do
      expect(published.flat_map(&:usage).uniq)
        .to include("KsefTokenEncryption", "SymmetricKeyEncryption")
    end

    it "issues them to the Ministry of Finance" do
      expect(published.map { |certificate| certificate.x509.subject.to_s })
        .to all(include("Ministerstwo Finans"))
    end

    # §10.2's first derivation claim.
    it "sets certificateId to the base64 SHA-256 of the DER certificate" do
      expect(published.map { |c| base64_sha256(c.x509.to_der) })
        .to eq(published.map(&:certificate_id))
    end

    # §10.2's second, and the load-bearing one: publicKeyId is the selector sent back on
    # every encrypted request.
    it "sets publicKeyId to the base64 SHA-256 of the DER SubjectPublicKeyInfo" do
      expect(published.map { |c| base64_sha256(c.public_key.public_to_der) })
        .to eq(published.map(&:public_key_id))
    end

    # A 2048-bit key is the floor §4.3 records for signatures; the wrapping keys should be
    # at least that. Worth knowing, because it bounds the OAEP plaintext limit.
    it "publishes RSA keys of at least 2048 bits" do
      expect(published.map { |c| c.public_key.n.num_bits }).to all(be >= 2048)
    end

    it "selects a currently valid certificate for both usages" do
      expect(keys.token_encryption.valid_at?).to be(true)
      expect(keys.symmetric_key_encryption.valid_at?).to be(true)
    end
  end

  # The stored `KSEF_TEST_NIP` / `KSEF_TEST_TOKEN` pair is exactly what this flow needs —
  # and unlike the XAdES flow it needs no PESEL, so it can reuse the provisioned identity
  # rather than registering a fresh test person each run.
  describe "the full KSeF-token flow" do
    let(:client) { Ksef::Auth::Client.new(connection) }

    def credential
      Ksef::Auth::Token.new(context_nip: ENV.fetch("KSEF_TEST_NIP"), token: ENV.fetch("KSEF_TEST_TOKEN"))
    end

    before do
      skip "set KSEF_TEST_NIP and KSEF_TEST_TOKEN to exercise the token flow" unless
        ENV["KSEF_TEST_NIP"] && ENV["KSEF_TEST_TOKEN"]
    end

    def authenticate
      challenge = client.challenge
      request = credential.authentication_request(
        challenge: challenge, certificate: keys.token_encryption
      )
      initiated = client.submit_ksef_token(request)
      client.authenticate!(initiated.reference_number, token: initiated.authentication_token)
      client.redeem(token: initiated.authentication_token)
    end

    # The whole crypto module in one assertion: KSeF only issues these if it unwrapped our
    # RSA-OAEP ciphertext and found the token beside its own challenge timestamp.
    it "yields a usable token pair, so KSeF decrypted what we wrapped" do
      tokens = authenticate

      expect(tokens.access_token.token).to be_a(String)
      expect(tokens).not_to be_expired
    end

    # §4.5 records, from first-tier documentation, that the timestamp acts as a replay
    # nonce so a captured ciphertext cannot be reused in a later session. This is the first
    # live check of that claim: a failure here is a **ledger finding** — the nonce is not
    # enforced as documented — rather than a regression in this gem.
    it "refuses a token encrypted against a challenge timestamp that is not the server's" do
      challenge = client.challenge
      stale = challenge.with(timestamp_ms: challenge.timestamp_ms - 600_000)
      request = credential.authentication_request(challenge: stale, certificate: keys.token_encryption)
      initiated = client.submit_ksef_token(request)

      expect { client.authenticate!(initiated.reference_number, token: initiated.authentication_token) }
        .to raise_error(Ksef::AuthenticationError)
    end
  end
end
