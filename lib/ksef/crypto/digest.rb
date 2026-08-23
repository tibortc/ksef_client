# frozen_string_literal: true

module Ksef
  module Crypto
    # The SHA-256-and-size pair KSeF wants beside a payload (docs/REFERENCE.md §11.1).
    #
    # `POST /sessions/online/{ref}/invoices` carries **four** integrity values — the hash
    # and size of the plaintext invoice *and* of the ciphertext. Computing one over the
    # wrong artifact is an easy mistake and a silent one, which is why
    # {Ksef::Crypto::Encryptor#seal} produces both at once rather than leaving a caller to
    # pair them up.
    #
    # `size` is a **byte** count, not a character count. An invoice full of Polish
    # characters has more bytes than characters, and reporting the shorter figure would be
    # rejected downstream.
    Digest = Data.define(:bytes, :size) do
      # @param content [String] the exact bytes that will be sent
      def self.of(content) = new(bytes: Crypto.sha256(content), size: content.bytesize)

      # @return [String] the wire form: base64 of the digest, always 44 characters, which
      #   is what the contract's `Sha256HashBase64` constrains it to
      def base64 = Crypto.encode(bytes)
    end
  end
end
