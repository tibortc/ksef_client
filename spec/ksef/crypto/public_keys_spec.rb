# frozen_string_literal: true

require_relative "../../support/crypto_fixtures"

RSpec.describe Ksef::Crypto::PublicKeys do
  subject(:keys) { described_class.new(connection, clock: -> { now }) }

  let(:endpoint) { "https://api-test.ksef.mf.gov.pl/v2/security/public-key-certificates" }
  let(:connection) { Ksef::HTTP::Connection.build(Ksef::Configuration.new(env: :test)) }
  let(:now) { CryptoFixtures::NOW }

  # Methods rather than `let`s: the fixture memoises the keypair and certificate underneath,
  # so recomputing a payload is nearly free, and the group is already at the memoised-helper
  # limit with the four above.
  def symmetric = CryptoFixtures.payload

  def token = CryptoFixtures.payload(usage: [Ksef::Crypto::Certificate::KSEF_TOKEN_ENCRYPTION])

  def stub_list(*payloads, status: 200)
    stub_request(:get, endpoint).to_return(
      status: status, body: JSON.dump(payloads), headers: { "Content-Type" => "application/json" }
    )
  end

  describe "#all" do
    it "fetches the published list and maps it to certificates" do
      stub_list(symmetric, token)

      expect(keys.all.map(&:usage).flatten)
        .to contain_exactly("SymmetricKeyEncryption", "KsefTokenEncryption")
    end

    # The contract declares no `security` for this operation, so it works before any
    # authentication — which is what lets a client fetch keys on its way to authenticating.
    it "sends no Authorization header" do
      stub = stub_list(symmetric)
      keys.all

      expect(stub.with { |request| !request.headers.key?("Authorization") }).to have_been_made
    end

    it "caches within the TTL, so a session open does not re-fetch" do
      stub_list(symmetric)
      3.times { keys.all }

      expect(a_request(:get, endpoint)).to have_been_made.once
    end

    it "tolerates an empty list without raising" do
      stub_list

      expect(keys.all).to eq([])
    end
  end

  describe "cache expiry" do
    # §10.2: an emergency rotation revokes a key and drops it from the list immediately,
    # so an indefinite cache would keep wrapping payloads under a withdrawn key.
    it "re-fetches once the TTL has lapsed" do
      stub_list(symmetric)
      moment = now
      cache = described_class.new(connection, ttl: 60, clock: -> { moment })
      cache.all
      moment += 61
      cache.all

      expect(a_request(:get, endpoint)).to have_been_made.twice
    end

    it "still caches right up to the TTL" do
      stub_list(symmetric)
      moment = now
      cache = described_class.new(connection, ttl: 60, clock: -> { moment })
      cache.all
      moment += 59
      cache.all

      expect(a_request(:get, endpoint)).to have_been_made.once
    end

    it "refetches on every call when the TTL is zero" do
      stub_list(symmetric)
      cache = described_class.new(connection, ttl: 0, clock: -> { now })
      2.times { cache.all }

      expect(a_request(:get, endpoint)).to have_been_made.twice
    end
  end

  describe "#refresh!" do
    it "discards the cache and reads the list again" do
      stub_list(symmetric)
      keys.all
      keys.refresh!

      expect(a_request(:get, endpoint)).to have_been_made.twice
    end

    it "picks up a newly published certificate the TTL would have hidden" do
      stub_request(:get, endpoint).to_return(
        { status: 200, body: JSON.dump([]), headers: { "Content-Type" => "application/json" } },
        { status: 200, body: JSON.dump([symmetric]), headers: { "Content-Type" => "application/json" } }
      )

      expect(keys.all).to be_empty
      expect(keys.refresh!.size).to eq(1)
    end
  end

  describe "#for_usage" do
    it "selects by usage" do
      stub_list(symmetric, token)

      expect(keys.for_usage(Ksef::Crypto::Certificate::KSEF_TOKEN_ENCRYPTION).public_key_id)
        .to eq(token["publicKeyId"])
    end

    # The rule §10.2 documents, and it matters: during a planned rotation both the outgoing
    # and incoming certificates are valid for the same usage, and picking the older one
    # wastes the overlap the Ministry published it for.
    it "prefers the latest validFrom when several are valid at once" do
      older = CryptoFixtures.payload(valid_from: "2024-01-01T00:00:00Z", valid_to: "2027-01-01T00:00:00Z")
      newer = CryptoFixtures.payload(valid_from: "2026-06-01T00:00:00Z", valid_to: "2030-01-01T00:00:00Z",
                                     key: CryptoFixtures.other_keypair)
      stub_list(older, newer)

      expect(keys.symmetric_key_encryption.public_key_id).to eq(newer["publicKeyId"])
    end

    it "ignores a certificate that is not yet valid" do
      future = CryptoFixtures.payload(valid_from: "2030-01-01T00:00:00Z", valid_to: "2031-01-01T00:00:00Z",
                                      key: CryptoFixtures.other_keypair)
      stub_list(symmetric, future)

      expect(keys.symmetric_key_encryption.public_key_id).to eq(symmetric["publicKeyId"])
    end

    it "honours an explicit moment of use, not just now" do
      stub_list(symmetric)

      expect { keys.symmetric_key_encryption(at: Time.utc(2030, 1, 1)) }
        .to raise_error(Ksef::CryptoError, /valid at 2030-01-01/)
    end

    it "reports what the list did carry when nothing matches" do
      stub_list(token)

      expect { keys.symmetric_key_encryption }
        .to raise_error(Ksef::CryptoError, /1 certificate\(s\) covering \["KsefTokenEncryption"\]/)
    end

    # A typo would otherwise read as "the Ministry publishes no such key", which sends the
    # reader looking in the wrong place entirely.
    it "distinguishes an unknown usage from an absent one" do
      expect { keys.for_usage("SymmetricKeyEncription") }
        .to raise_error(Ksef::CryptoError, /Unknown certificate usage/)
      expect(a_request(:get, endpoint)).not_to have_been_made
    end
  end

  describe "#token_encryption" do
    it "selects the key that wraps a KSeF token during authentication" do
      stub_list(symmetric, token)

      expect(keys.token_encryption.usage).to eq(["KsefTokenEncryption"])
    end
  end

  describe "#with_key_rotation" do
    # Built through the real parser rather than hand-assembled, so the `#code` the
    # remediation switches on is the one the error handler would actually produce from the
    # 400 body §10.2 describes.
    let(:unknown_key) do
      problem = Ksef::ProblemDetails.parse(
        status: 400,
        body: { "status" => 400, "title" => "Bad Request",
                "errors" => [{ "code" => described_class::UNKNOWN_KEY_CODE,
                               "description" => "Przesłany identyfikator klucza jest nieznany" }] }
      )
      Ksef::ApiError.new(problem.summary, problem: problem)
    end

    # The block selects inside itself, which is the documented shape: the point of the
    # retry is that the second attempt carries a *different* key identifier, so a
    # pre-selected certificate captured outside would defeat it.
    it "re-fetches the list and runs the operation again on a 21470" do
      stub_list(symmetric)
      attempts = 0

      result = keys.with_key_rotation do
        attempts += 1
        selected = keys.symmetric_key_encryption.public_key_id
        raise unknown_key if attempts == 1

        selected
      end

      expect(attempts).to eq(2)
      expect(result).to eq(symmetric["publicKeyId"])
      expect(a_request(:get, endpoint)).to have_been_made.twice
    end

    # Remediation, not a blind replay: a 21470 means the request was declined outright, so
    # there is no duplicate to create. Any *other* API error must surface untouched, which
    # is what keeps DESIGN.md §6.7's never-retry-a-POST rule intact.
    it "does not retry any other API error" do
      attempts = 0

      expect do
        keys.with_key_rotation do
          attempts += 1
          raise Ksef::ApiError, "rejected"
        end
      end.to raise_error(Ksef::ApiError, "rejected")
      expect(attempts).to eq(1)
    end

    it "re-raises when the second attempt fails too, rather than looping" do
      stub_list(symmetric)
      attempts = 0

      expect do
        keys.with_key_rotation do
          attempts += 1
          raise unknown_key
        end
      end.to raise_error(Ksef::ApiError)
      expect(attempts).to eq(2)
    end

    it "passes the block's value through when nothing goes wrong" do
      expect(keys.with_key_rotation { :sent }).to eq(:sent)
    end
  end

  it "is safe to share across threads" do
    stub_list(symmetric)
    results = Array.new(8) { Thread.new { keys.symmetric_key_encryption.public_key_id } }.map(&:value)

    expect(results.uniq).to eq([symmetric["publicKeyId"]])
    expect(a_request(:get, endpoint)).to have_been_made.once
  end
end
