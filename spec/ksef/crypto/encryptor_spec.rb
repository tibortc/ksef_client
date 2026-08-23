# frozen_string_literal: true

require_relative "../../support/crypto_fixtures"

RSpec.describe Ksef::Crypto::Encryptor do
  subject(:encryptor) { described_class.new(key: nist_key, iv: nist_iv) }

  # NIST SP 800-38A, appendix F.2.5 — CBC-AES256.Encrypt. Four blocks, no padding in the
  # published vector, so PKCS#7 appends a fifth block to our output and the first 64 bytes
  # must match byte for byte.
  let(:nist_key) { hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4") }
  let(:nist_iv) { hex("000102030405060708090a0b0c0d0e0f") }
  let(:nist_plaintext) do
    hex("6bc1bee22e409f96e93d7e117393172a" \
        "ae2d8a571e03ac9c9eb76fac45af8e51" \
        "30c81c46a35ce411e5fbc1191a0a52ef" \
        "f69f2445df4f9b17ad2b417be66c3710")
  end
  let(:nist_ciphertext) do
    hex("f58c4c04d6e5f1ba779eabfb5f7bfbd6" \
        "9cfc4e967edb808d679f777bc6702c7d" \
        "39f23369a9d9bacfa530e26304231461" \
        "b2eb05e2c39be9fcda6c19078c6a9d1b")
  end

  def hex(string) = [string].pack("H*")

  describe ".generate" do
    it "produces a 32-byte key and a 16-byte IV from the CSPRNG" do
      generated = described_class.generate

      expect(generated.iv.bytesize).to eq(16)
      expect(generated.encrypt("x").bytesize).to eq(16)
    end

    it "produces a different key each time, since §10.1 recommends one per session" do
      expect(described_class.generate.iv).not_to eq(described_class.generate.iv)
    end
  end

  describe "#initialize" do
    it "refuses a key of the wrong length, which would silently select a weaker cipher" do
      expect { described_class.new(key: "short", iv: nist_iv) }
        .to raise_error(Ksef::CryptoError, /key must be 32 bytes, got 5/)
    end

    it "refuses an IV of the wrong length" do
      expect { described_class.new(key: nist_key, iv: "short") }
        .to raise_error(Ksef::CryptoError, /iv must be 16 bytes, got 5/)
    end

    # 32 characters, 64 bytes. A character count would have waved this through and then
    # produced ciphertext under a key OpenSSL had truncated.
    it "counts bytes rather than characters when rejecting" do
      multibyte = "ż" * 32

      expect(multibyte.size).to eq(32)
      expect { described_class.new(key: multibyte, iv: nist_iv) }
        .to raise_error(Ksef::CryptoError, /got 64/)
    end

    it "is frozen, so a shared client cannot have its key material mutated" do
      expect(encryptor).to be_frozen
      expect(encryptor.iv).to be_frozen
    end
  end

  describe "#encrypt" do
    it "matches the NIST SP 800-38A CBC-AES256 vector" do
      expect(encryptor.encrypt(nist_plaintext)[0, 64]).to eq(nist_ciphertext)
    end

    # PKCS#7 always adds something, so a whole number of blocks grows by a whole block.
    it "pads with PKCS#7, adding a full block to an exact multiple" do
      expect(encryptor.encrypt(nist_plaintext).bytesize).to eq(80)
      expect(encryptor.encrypt("a" * 16).bytesize).to eq(32)
      expect(encryptor.encrypt("a" * 15).bytesize).to eq(16)
    end

    # docs/REFERENCE.md §14.1, and the reason this spec exists at all: upstream's prose
    # says the IV is prefixed to the ciphertext. It is not, and the contract's own worked
    # example proves it — 6480 plaintext bytes become 6496, which is one block of padding
    # and no room for a 16-byte IV.
    it "returns bare ciphertext, with no IV prefixed" do
      ciphertext = encryptor.encrypt(nist_plaintext)

      expect(ciphertext[0, 16]).not_to eq(nist_iv)
      expect(ciphertext[0, 16]).to eq(nist_ciphertext[0, 16])
    end

    it "reproduces the contract's own worked size example" do
      expect(encryptor.encrypt("a" * 6480).bytesize).to eq(6496)
    end

    it "returns binary, not the encoding the plaintext happened to carry" do
      expect(encryptor.encrypt("zażółć").encoding).to eq(Encoding::BINARY)
    end

    # Unlike RSA-OAEP, which is randomised: CBC under a fixed key and IV is deterministic,
    # which is what makes the NIST vector above checkable in the first place.
    it "is deterministic for a fixed key and IV" do
      first = encryptor.encrypt("payload")
      second = described_class.new(key: nist_key, iv: nist_iv).encrypt("payload")

      expect(first).to eq(second)
    end
  end

  describe "#decrypt" do
    it "round-trips UTF-8, byte for byte" do
      xml = "<Faktura>zażółć gęślą jaźń</Faktura>"

      expect(encryptor.decrypt(encryptor.encrypt(xml)).force_encoding("UTF-8")).to eq(xml)
    end

    it "round-trips a payload of exactly one block" do
      expect(encryptor.decrypt(encryptor.encrypt("a" * 16))).to eq("a" * 16)
    end

    it "fails under a different key" do
      other = described_class.new(key: nist_iv * 2, iv: nist_iv)

      expect { other.decrypt(encryptor.encrypt("payload")) }.to raise_error(OpenSSL::OpenSSLError)
    end
  end

  describe "#seal" do
    subject(:sealed) { encryptor.seal(xml) }

    let(:xml) { "<Faktura>zażółć</Faktura>" }

    # §11.1: the send-invoice request carries the hash *and* size of both forms, and
    # hashing the wrong artifact is a silent error only the server can catch. Producing
    # both at once is what makes it unmistakable.
    it "measures the plaintext and the ciphertext separately" do
      expect(sealed.plaintext_digest).to eq(Ksef::Crypto::Digest.of(xml))
      expect(sealed.ciphertext_digest).to eq(Ksef::Crypto::Digest.of(sealed.ciphertext))
      expect(sealed.plaintext_digest).not_to eq(sealed.ciphertext_digest)
    end

    it "reports the plaintext size in bytes, not characters" do
      expect(sealed.plaintext_digest.size).to eq(xml.bytesize)
      expect(sealed.plaintext_digest.size).to be > xml.size
    end

    it "reports a ciphertext size that is a whole number of blocks and larger" do
      expect(sealed.ciphertext_digest.size % Ksef::Crypto::BLOCK_BYTES).to eq(0)
      expect(sealed.ciphertext_digest.size).to be > sealed.plaintext_digest.size
    end

    it "yields ciphertext that decrypts back to the plaintext it measured" do
      expect(encryptor.decrypt(sealed.ciphertext).force_encoding("UTF-8")).to eq(xml)
    end

    describe "#content" do
      it "is the base64 of the ciphertext, ready to send" do
        expect(Ksef::Crypto.decode(sealed.content)).to eq(sealed.ciphertext)
      end
    end
  end

  describe "#encryption_info" do
    subject(:info) { encryptor.encryption_info(certificate) }

    let(:certificate) { CryptoFixtures.certificate }

    it "names the three fields of the contract's EncryptionInfo" do
      expect(info.keys).to contain_exactly(:encryptedSymmetricKey, :initializationVector, :publicKeyId)
    end

    it "wraps the symmetric key so KSeF's private key recovers it exactly" do
      wrapped = Ksef::Crypto.decode(info[:encryptedSymmetricKey])

      expect(CryptoFixtures.keypair.decrypt(wrapped, Ksef::Crypto::OAEP)).to eq(nist_key)
    end

    it "sends the IV base64-encoded and separate, per §14.1" do
      expect(Ksef::Crypto.decode(info[:initializationVector])).to eq(nist_iv)
    end

    # Nullable in the contract, always sent here: without it a key rotation turns a
    # decryptable payload into an undecryptable one with nothing to diagnose it by.
    it "always names the key that did the wrapping" do
      expect(info[:publicKeyId]).to eq(certificate.public_key_id)
      expect(info[:publicKeyId].length).to eq(44)
    end
  end

  describe "redaction" do
    # DESIGN.md §4.5 forbids leaking symmetric keys and IVs at default log level.
    it "keeps key material out of #to_s and #inspect" do
      expect(encryptor.to_s).to eq("[REDACTED]")
      expect(encryptor.inspect).to eq("#<Ksef::Crypto::Encryptor key=[REDACTED] iv=[REDACTED]>")
    end

    it "leaks neither the key nor the IV through interpolation" do
      line = "encryptor=#{encryptor}"

      expect(line).not_to include(nist_key)
      expect(line).not_to include(nist_iv)
    end
  end
end
