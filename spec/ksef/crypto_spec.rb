# frozen_string_literal: true

require_relative "../support/crypto_fixtures"

# The primitives, checked against published vectors rather than against themselves.
#
# **On golden vectors.** DESIGN.md §6.4 asked for encryption vectors ported from the
# official C# client. There are none to port: neither reference client commits fixed
# plaintext/ciphertext pairs, and `Compatibility/CryptoCompat*.cs` are runtime polyfills,
# not tests (docs/REFERENCE.md §10.1). NIST and FIPS vectors serve the purpose better
# anyway — they pin the primitives to their standards rather than to another
# implementation's output, and OpenSSL reproduces them by construction.
#
# What genuinely needed pinning was never the primitives but the *framing*: whether the IV
# is prefixed to the ciphertext (§14.1) and which digest MGF1 uses. Both are asserted
# below and in `encryptor_spec.rb`.
RSpec.describe Ksef::Crypto do
  describe "the ledgered parameters" do
    # §10.1. A change here is a change to what KSeF can decrypt, so these are asserted as
    # values, not merely used.
    it "is AES-256-CBC with a 256-bit key and a 128-bit IV" do
      expect(described_class::CIPHER).to eq("aes-256-cbc")
      expect(described_class::KEY_BYTES).to eq(32)
      expect(described_class::IV_BYTES).to eq(16)
    end

    # The trap: OpenSSL's MGF1 digest defaults to SHA-1, so naming only `rsa_oaep_md`
    # yields a different scheme that fails at the far end rather than here.
    it "states the MGF1 digest as well as the OAEP digest" do
      expect(described_class::OAEP).to eq(
        rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256"
      )
    end
  end

  describe ".encode" do
    it "emits strict base64, with no line breaks even for a long value" do
      expect(described_class.encode("a" * 1024)).not_to include("\n")
    end

    it "does not pad-strip, so the value stays decodable" do
      expect(described_class.decode(described_class.encode("abc"))).to eq("abc")
    end
  end

  describe ".decode" do
    it "round-trips binary that is not valid UTF-8" do
      bytes = (0..255).to_a.pack("C*")

      expect(described_class.decode(described_class.encode(bytes))).to eq(bytes)
    end

    # Deliberately lenient on input: `"m0"` raises on a line break, and how a server wraps
    # a long base64 value is its business, not ours.
    it "accepts a line-wrapped value, which strict decoding would reject" do
      wrapped = ["x" * 200].pack("m")

      expect(wrapped).to include("\n")
      expect(described_class.decode(wrapped)).to eq("x" * 200)
    end

    it "treats nil as empty rather than raising" do
      expect(described_class.decode(nil)).to eq("")
    end
  end

  describe ".sha256" do
    # FIPS 180-4 / RFC 6234.
    it "matches the published vector for \"abc\"" do
      expect(described_class.sha256("abc").unpack1("H*"))
        .to eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    end

    it "matches the published vector for the empty string" do
      expect(described_class.sha256("").unpack1("H*"))
        .to eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    end
  end

  describe ".rsa_encrypt" do
    let(:key) { CryptoFixtures.keypair }

    it "produces exactly one RSA block" do
      expect(described_class.rsa_encrypt("payload", key.public_key).bytesize).to eq(256)
    end

    it "is decryptable with the same OAEP parameters" do
      ciphertext = described_class.rsa_encrypt("payload", key.public_key)

      expect(key.decrypt(ciphertext, described_class::OAEP)).to eq("payload")
    end

    # The assertion that the parameters are what we claim. If MGF1 were SHA-1 this would
    # succeed, and nothing else in the suite would notice.
    it "is not decryptable with MGF1-SHA1, so the digest choice is real" do
      ciphertext = described_class.rsa_encrypt("payload", key.public_key)
      sha1_mgf1 = described_class::OAEP.merge(rsa_mgf1_md: "sha1")

      expect { key.decrypt(ciphertext, sha1_mgf1) }.to raise_error(OpenSSL::OpenSSLError)
    end

    # `k - 2*hLen - 2` = `256 - 64 - 2`. With SHA-1 the limit would be 214, so this
    # pins hLen at 32 without trusting the option name.
    it "carries 190 bytes but not 191, which pins the digest at SHA-256" do
      expect(described_class.rsa_encrypt("a" * described_class::MAX_OAEP_PLAINTEXT_BYTES, key.public_key).bytesize)
        .to eq(256)
      expect { described_class.rsa_encrypt("a" * 191, key.public_key) }
        .to raise_error(OpenSSL::OpenSSLError)
    end

    # Both plaintexts KSeF asks us to wrap are far inside the limit above; worth stating,
    # because the limit is the one way this call fails on well-formed input.
    it "comfortably fits the two plaintexts KSeF actually asks for" do
      symmetric_key = 32
      token_and_timestamp = "#{"T" * 64}|1787824800000".bytesize

      expect([symmetric_key, token_and_timestamp].max).to be < described_class::MAX_OAEP_PLAINTEXT_BYTES
    end
  end
end
