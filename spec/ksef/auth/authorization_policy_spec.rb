# frozen_string_literal: true

RSpec.describe Ksef::Auth::AuthorizationPolicy do
  describe ".coerce" do
    it "passes nil through, since the policy is optional" do
      expect(described_class.coerce(nil)).to be_nil
    end

    it "passes an existing policy through untouched" do
      policy = described_class.new(addresses: %w[10.0.0.1])

      expect(described_class.coerce(policy)).to be(policy)
    end

    it "builds one from a Hash" do
      expect(described_class.coerce(addresses: %w[10.0.0.1]).addresses).to eq(%w[10.0.0.1])
    end

    it "rejects an unknown key with a ValidationError, not an ArgumentError" do
      expect { described_class.coerce(ipv6: ["::1"]) }
        .to raise_error(Ksef::ValidationError, /Unknown allowed_ips key\(s\) :ipv6/)
    end
  end

  describe "#entries" do
    # The schema sequences Ip4Address, Ip4Range, Ip4Mask. Emitting them in the caller's
    # order would be rejected by KSeF rather than caught locally.
    it "yields name/value pairs in schema order regardless of construction order" do
      policy = described_class.new(masks: %w[10.0.0.0/8], ranges: %w[10.0.0.1-10.0.0.9], addresses: %w[10.0.0.1])

      expect(policy.entries).to eq([["Ip4Address", "10.0.0.1"], ["Ip4Range", "10.0.0.1-10.0.0.9"],
                                    ["Ip4Mask", "10.0.0.0/8"]])
    end

    it "repeats an element once per value" do
      expect(described_class.new(addresses: %w[10.0.0.1 10.0.0.2]).entries.size).to eq(2)
    end
  end

  describe "validation" do
    it "rejects a policy with nothing in it" do
      expect { described_class.new }.to raise_error(Ksef::ValidationError, /lists no addresses/)
    end

    it "accepts the ten entries the schema permits" do
      expect(described_class.new(addresses: Array.new(10) { |i| "10.0.0.#{i}" })).not_to be_empty
    end

    it "rejects an eleventh, naming the list that overflowed" do
      expect { described_class.new(ranges: Array.new(11, "10.0.0.1-10.0.0.9")) }
        .to raise_error(Ksef::ValidationError, /allowed_ips\[:ranges\] has 11 entries/)
    end

    it "wraps a bare value in an array, so a single address need not be one" do
      expect(described_class.new(addresses: "10.0.0.1").addresses).to eq(%w[10.0.0.1])
    end

    it "is frozen, along with its lists" do
      policy = described_class.new(addresses: %w[10.0.0.1])

      expect(policy).to be_frozen
      expect(policy.addresses).to be_frozen
    end
  end
end
