# frozen_string_literal: true

RSpec.describe Ksef::Crypto::Digest do
  describe ".of" do
    it "carries the raw digest and the byte count" do
      digest = described_class.of("abc")

      expect(digest.bytes.unpack1("H*"))
        .to eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
      expect(digest.size).to eq(3)
    end

    # The mistake this guards: `String#size` counts characters, and every KSeF artifact is
    # full of Polish ones. Reporting 24 where the API expects 33 fails the send.
    it "counts bytes, not characters" do
      xml = "<Faktura>zażółć gęślą</Faktura>"

      expect(xml.size).to eq(31)
      expect(described_class.of(xml).size).to eq(xml.bytesize)
      expect(described_class.of(xml).size).to be > xml.size
    end

    it "hashes the bytes, so the encoding a String is tagged with cannot change the result" do
      utf8 = "zażółć"

      expect(described_class.of(utf8).bytes).to eq(described_class.of(utf8.dup.force_encoding(Encoding::BINARY)).bytes)
    end

    it "handles an empty payload" do
      expect(described_class.of("").size).to eq(0)
    end
  end

  describe "#base64" do
    # The contract's `Sha256HashBase64` is `minLength: 44, maxLength: 44`.
    it "is 44 characters, as the contract constrains every hash field to be" do
      expect(described_class.of("anything").base64.length).to eq(44)
    end

    it "is the base64 of the raw digest" do
      digest = described_class.of("abc")

      expect(digest.base64).to eq([digest.bytes].pack("m0"))
    end
  end

  it "compares by value, so two digests of the same payload are equal" do
    once = described_class.of("abc")
    again = described_class.of("abc".dup)

    expect(once).to eq(again)
  end
end
