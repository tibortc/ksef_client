# frozen_string_literal: true

require_relative "../../tasks/ksef_bootstrap"
require_relative "../support/signing_fixtures"

RSpec.describe KsefBootstrap do
  let(:base) { "https://api-test.ksef.mf.gov.pl/v2" }
  let(:io) { StringIO.new }
  let(:configuration) { Ksef::Configuration.new(env: :test) }

  def json(body, status: 200)
    { status: status, body: JSON.dump(body), headers: { "Content-Type" => "application/json" } }
  end

  describe KsefBootstrap::Identifiers do
    # Confirmed the way §6a.1 confirmed the NIP algorithm — against the values upstream
    # itself publishes, not against a recollection of the rules.
    it "agrees with every PESEL in the upstream documentation" do
      %w[15062788702 30112206276 38092277125 88102341294].each do |pesel|
        expect(described_class.pesel_valid?(pesel)).to be(true), "rejected upstream's own #{pesel}"
      end
    end

    it "rejects a PESEL whose check digit is wrong" do
      expect(described_class.pesel_valid?("15062788703")).to be(false)
    end

    it "rejects anything that is not eleven digits" do
      expect(described_class.pesel_valid?("1506278870")).to be(false)
      expect(described_class.pesel_valid?(nil)).to be(false)
    end

    it "generates PESELs that pass its own check" do
      random = Random.new(99)

      expect(Array.new(50) { described_class.pesel(random) }).to all(satisfy { |p| described_class.pesel_valid?(p) })
    end

    # A generated NIP has to satisfy both the checksum and the auth schema's TNIP shape
    # (§4.1) — first digit non-zero, digits 2-3 not both zero.
    it "generates NIPs the library's own validator accepts" do
      random = Random.new(7)

      expect(Array.new(50) { described_class.nip(random) }).to all(satisfy { |n| Ksef::FA3::NIP.valid?(n) })
    end

    it "is reproducible from a seeded Random, so a failed run can be repeated" do
      first = described_class.nip(Random.new(42))

      expect(described_class.nip(Random.new(42))).to eq(first)
    end

    it "discards a draw whose check digit would be 10, which is unrepresentable" do
      expect(described_class.nip_candidate(Random.new(3))).to(satisfy { |n| n.nil? || n.length == 10 })
    end

    it "fails loudly rather than looping for ever if the arithmetic is wrong" do
      expect { described_class.nip(Random.new, attempts: 0) }.to raise_error(/algorithm is wrong/)
    end
  end

  describe KsefBootstrap::Certificate do
    it "carries the PESEL as PNOPL-<pesel> in serialNumber, one of §4.4's patterns" do
      certificate, = described_class.personal(pesel: "15062788702")

      expect(certificate.subject.to_s).to include("serialNumber=PNOPL-15062788702")
    end

    it "returns a key that matches the certificate" do
      certificate, key = described_class.personal(pesel: "15062788702")

      expect(certificate.check_private_key(key)).to be(true)
    end

    it "is valid from a minute ago, so clock skew cannot make it not-yet-valid" do
      certificate, = described_class.personal(pesel: "15062788702")

      expect(certificate.not_before).to be < Time.now
    end

    it "uses a random serial, so two runs are distinguishable" do
      first, = described_class.personal(pesel: "15062788702")
      second, = described_class.personal(pesel: "15062788702")

      expect(first.serial).not_to eq(second.serial)
    end
  end

  describe KsefBootstrap::Runner do
    # The hard rule: never PROD from any script. Checked against the environment's declared
    # capability rather than its name, so a `custom` environment cannot slip past either.
    describe "environment guard" do
      it "refuses PROD" do
        expect { described_class.new(configuration: Ksef::Configuration.new(env: :prod)) }
          .to raise_error(ArgumentError, /Refusing to bootstrap against prod/)
      end

      it "refuses DEMO, which has no test-data endpoints" do
        expect { described_class.new(configuration: Ksef::Configuration.new(env: :demo)) }
          .to raise_error(ArgumentError, /never touch DEMO or PROD/)
      end

      it "accepts TEST" do
        expect { described_class.new(configuration: configuration, io: io) }.not_to raise_error
      end
    end

    describe "#call" do
      # A memoised certificate and a no-op sleeper: the poll interval is real behaviour
      # (two seconds between polls), and waiting for it in eight examples is not.
      subject(:result) { runner.call }

      let(:reference) { "20260822-AU-AAAAAAAAAA-BBBBBBBBBB-CC" }
      let(:runner) do
        described_class.new(configuration: configuration, io: io, random: Random.new(5),
                            certificate: issued.fetch(:certificate), key: issued.fetch(:key),
                            sleeper: ->(_) {})
      end

      before do
        stub_request(:post, "#{base}/testdata/person").to_return(json({}))
        stub_request(:post, "#{base}/auth/challenge").to_return(
          json({ "challenge" => "20250604-CR-461EA5B000-537A6BA15D-D7",
                 "timestamp" => "2026-08-22T10:00:00Z", "timestampMs" => 1, "clientIp" => "203.0.113.7" })
        )
        stub_request(:post, "#{base}/auth/xades-signature").to_return(
          json({ "referenceNumber" => reference,
                 "authenticationToken" => { "token" => "auth.jwt", "validUntil" => "2026-08-22T10:10:00Z" } },
               status: 202)
        )
        stub_request(:get, "#{base}/auth/#{reference}").to_return(
          json({ "status" => { "code" => 100, "description" => "W toku" } }),
          json({ "status" => { "code" => 200, "description" => "Sukces" } })
        )
        stub_request(:post, "#{base}/auth/token/redeem").to_return(
          json({ "accessToken" => { "token" => "access.jwt", "validUntil" => "2026-08-22T10:15:00Z" },
                 "refreshToken" => { "token" => "refresh.jwt", "validUntil" => "2026-08-29T10:00:00Z" } })
        )
        stub_request(:post, "#{base}/tokens").to_return(
          json({ "token" => "ksef.token.value", "referenceNumber" => "20260822-TK-1111111111-2222222222-DD" },
               status: 202)
        )
      end

      def issued = SigningFixtures.personal

      it "returns the pair nightly.yml needs" do
        expect(result[:token]).to eq("ksef.token.value")
        expect(Ksef::FA3::NIP.valid?(result[:nip])).to be(true)
      end

      it "registers the invented identifiers through the unauthenticated test-data endpoint" do
        result

        matched = a_request(:post, "#{base}/testdata/person").with do |request|
          body = JSON.parse(request.body)
          body["nip"] == result[:nip] && body["pesel"] == result[:pesel] && body["isBailiff"] == false
        end

        expect(matched).to have_been_made
      end

      it "sends no Authorization header to the test-data endpoint" do
        result

        expect(a_request(:post, "#{base}/testdata/person")
                 .with { |r| !r.headers.key?("Authorization") }).to have_been_made
      end

      it "submits a signed document, not the bare request" do
        result

        expect(a_request(:post, "#{base}/auth/xades-signature")
                 .with { |r| r.body.include?("<ds:SignatureValue>") }).to have_been_made
      end

      it "polls until the operation succeeds" do
        result

        expect(a_request(:get, "#{base}/auth/#{reference}")).to have_been_made.twice
      end

      it "mints the token with the access token, not the authentication token" do
        result

        expect(a_request(:post, "#{base}/tokens")
                 .with(headers: { "Authorization" => "Bearer access.jwt" })).to have_been_made
      end

      it "requests exactly the permissions the integration suite needs" do
        result

        matched = a_request(:post, "#{base}/tokens").with do |request|
          JSON.parse(request.body)["permissions"] == %w[InvoiceRead InvoiceWrite]
        end

        expect(matched).to have_been_made
      end

      it "generates a self-signed certificate when none is supplied" do
        described_class.new(configuration: configuration, io: io, random: Random.new(5),
                            sleeper: ->(_) {}).call

        expect(io.string).to include("generating a self-signed certificate")
      end

      it "uses a supplied certificate instead, for a real qualified one" do
        result

        expect(io.string).not_to include("generating a self-signed certificate")
      end

      it "insists on a key alongside a certificate" do
        expect { described_class.new(configuration: configuration, certificate: issued.fetch(:certificate)) }
          .to raise_error(ArgumentError, /must be given together/)
      end

      it "reports progress without printing any bearer token" do
        result
        output = io.string

        expect(output).to include("registered on TEST", "polling", "token minted")
        expect(output).not_to include("auth.jwt", "access.jwt", "refresh.jwt")
      end
    end
  end
end
