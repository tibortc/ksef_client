# frozen_string_literal: true

require_relative "../../support/crypto_fixtures"

RSpec.describe Ksef::Auth::Token do
  subject(:credential) { described_class.new(context_nip: "9999999999", token: "KSEF-TOKEN-VALUE") }

  let(:certificate) { CryptoFixtures.certificate(usage: [Ksef::Crypto::Certificate::KSEF_TOKEN_ENCRYPTION]) }
  let(:challenge) do
    Ksef::Auth::Challenge.from(
      "challenge" => "20250604-CR-461EA5B000-537A6BA15D-D7",
      "timestamp" => "2026-08-23T10:00:00Z",
      "timestampMs" => 1_787_824_800_000,
      "clientIp" => "203.0.113.7"
    )
  end

  # DESIGN.md §8's snippet constructs the credential exactly this way, so the signature is
  # part of the public contract rather than an internal detail.
  describe "the DESIGN.md §8 constructor" do
    it "accepts a NIP context and a token" do
      expect(credential.context_type).to eq(:nip)
      expect(credential.context_value).to eq("9999999999")
    end

    it "accepts an InternalId context instead" do
      internal = described_class.new(internal_id: "9999999999-12345", token: "t")

      expect(internal.context_identifier).to eq(type: "InternalId", value: "9999999999-12345")
    end

    it "insists on exactly one context, since a token belongs to exactly one" do
      expect { described_class.new(token: "t") }
        .to raise_error(Ksef::ValidationError, /exactly one of context_nip: or internal_id:/)
      expect { described_class.new(token: "t", context_nip: "1", internal_id: "2") }
        .to raise_error(Ksef::ValidationError, /got \[:nip, :internal_id\]/)
    end

    it "refuses a missing or empty token, and says where one comes from" do
      expect { described_class.new(context_nip: "1", token: nil) }
        .to raise_error(Ksef::ValidationError, %r{issued by POST /tokens})
      expect { described_class.new(context_nip: "1", token: "") }
        .to raise_error(Ksef::ValidationError, /A KSeF token is required/)
    end

    # Only Nip and InternalId, though the contract's enum has four: a token can only be
    # *issued* in those two contexts, so a token for the other two cannot exist (§4.1).
    it "offers only the two context types a token can exist in" do
      expect(described_class::CONTEXT_TYPES.keys).to eq(%i[nip internal_id])
    end
  end

  describe "#encrypted_token" do
    it "encrypts token|timestampMs under the published key" do
      encrypted = credential.encrypted_token(challenge: challenge, certificate: certificate)
      plaintext = CryptoFixtures.keypair.decrypt(Ksef::Crypto.decode(encrypted), Ksef::Crypto::OAEP)

      expect(plaintext).to eq("KSEF-TOKEN-VALUE|1787824800000")
    end

    it "sends the challenge's own milliseconds, where a seconds count would be 10 digits" do
      encrypted = credential.encrypted_token(challenge: challenge, certificate: certificate)
      plaintext = CryptoFixtures.keypair.decrypt(Ksef::Crypto.decode(encrypted), Ksef::Crypto::OAEP)

      expect(plaintext.split("|").last).to eq(challenge.timestamp_ms.to_s)
      expect(plaintext.split("|").last.length).to eq(13)
    end

    # §4.5: the timestamp is a replay nonce, so it has to be the server's own value. A
    # locally generated one silently fails to match, which is the worst kind of failure —
    # so refuse the bare String rather than accept it and guess.
    it "refuses a bare challenge String, because the timestamp cannot be invented" do
      expect { credential.encrypted_token(challenge: challenge.to_s, certificate: certificate) }
        .to raise_error(Ksef::AuthenticationError, /replay nonce/)
    end

    it "refuses a challenge whose response carried no timestampMs" do
      partial = Ksef::Auth::Challenge.from("challenge" => challenge.to_s)

      expect { credential.encrypted_token(challenge: partial, certificate: certificate) }
        .to raise_error(Ksef::AuthenticationError, /timestampMs/)
    end

    it "produces a different ciphertext each time, since OAEP is randomised" do
      first = credential.encrypted_token(challenge: challenge, certificate: certificate)
      second = credential.encrypted_token(challenge: challenge, certificate: certificate)

      expect(first).not_to eq(second)
    end
  end

  describe "#authentication_request" do
    subject(:request) { credential.authentication_request(challenge: challenge, certificate: certificate) }

    it "names the four required fields of InitTokenAuthenticationRequest" do
      expect(request.keys).to contain_exactly(:challenge, :contextIdentifier, :encryptedToken, :publicKeyId)
    end

    it "sends the challenge verbatim and names the key that encrypted the token" do
      expect(request[:challenge]).to eq("20250604-CR-461EA5B000-537A6BA15D-D7")
      expect(request[:publicKeyId]).to eq(certificate.public_key_id)
    end

    it "sends the context as the contract's type/value pair" do
      expect(request[:contextIdentifier]).to eq(type: "Nip", value: "9999999999")
    end

    # Cheaper to catch here than as a 21111 from the API, and the same check the XAdES
    # document applies to the same value.
    it "rejects a malformed challenge before spending a request on it" do
      stale = Ksef::Auth::Challenge.new(challenge: "nonsense", timestamp: nil, timestamp_ms: 1, client_ip: nil)

      expect { credential.authentication_request(challenge: stale, certificate: certificate) }
        .to raise_error(Ksef::ValidationError, /Challenge "nonsense" is malformed/)
    end

    describe "the optional authorization policy" do
      it "is omitted entirely unless asked for" do
        expect(request).not_to have_key(:authorizationPolicy)
      end

      it "restricts the resulting access token to the given IPs" do
        restricted = credential.authentication_request(
          challenge: challenge, certificate: certificate,
          allowed_ips: { addresses: ["192.168.0.10"], masks: ["172.16.0.0/16"] }
        )

        expect(restricted[:authorizationPolicy])
          .to eq(allowedIps: { ip4Addresses: ["192.168.0.10"], ip4Masks: ["172.16.0.0/16"] })
      end

      it "carries the same ten-entry cap the XAdES document enforces" do
        expect do
          credential.authentication_request(
            challenge: challenge, certificate: certificate,
            allowed_ips: { addresses: Array.new(11, "10.0.0.1") }
          )
        end.to raise_error(Ksef::ValidationError, /11 entries; the schema permits 10/)
      end
    end
  end

  describe "redaction" do
    # DESIGN.md §4.5. The token is a live credential, and `"auth=#{token}"` in a log line
    # is exactly how one escapes.
    it "keeps the token out of #to_s and #inspect" do
      expect(credential.to_s).to eq("[REDACTED]")
      expect(credential.inspect).to eq("#<Ksef::Auth::Token context=Nip:9999999999 token=[REDACTED]>")
    end

    it "still identifies the context, which is what makes the redacted form useful" do
      expect("credential=#{credential.inspect}").to include("Nip:9999999999")
      expect("credential=#{credential.inspect}").not_to include("KSEF-TOKEN-VALUE")
    end
  end

  it "is frozen, so a credential cannot be repointed at another context" do
    expect(credential).to be_frozen
  end
end
