# frozen_string_literal: true

module Ksef
  module UPO
    # A retrieved UPO, held as the exact bytes received (docs/REFERENCE.md §12).
    #
    # `xml` is deliberately a raw `String` and not a parsed document. The Ministry's XAdES
    # signature covers the octets, so anything that re-serialises them — even a lossless
    # round-trip through an XML library — risks producing a document that no longer
    # verifies. Parse a *copy* if you need to read it; archive this.
    #
    # `source` records where the bytes came from, because the two routes have different
    # properties worth knowing after the fact: `:storage` is the unmetered pre-signed link
    # (§14.2), `:api` the metered fallback.
    Document = Data.define(:xml, :published_hash, :source) do
      # SHA-256 of the bytes held, Base64 — the same form `x-ms-meta-hash` uses.
      def sha256 = Ksef::Crypto::Digest.of(xml).base64

      def size = xml.bytesize

      # Whether there is anything to check against at all. The pre-signed storage link
      # publishes `x-ms-meta-hash`; the metered API route publishes nothing.
      #
      # Split from {#verified?} rather than folded into it as a third state: "no hash was
      # published" and "the hash did not match" call for completely different responses, and
      # a predicate that answers both with one value invites treating an unverifiable
      # document as a corrupt one.
      def verifiable? = !published_hash.nil?

      # True only when a hash was published **and** the bytes match it. False for an
      # unverifiable document too — ask {#verifiable?} to tell the two apart.
      def verified? = verifiable? && sha256 == published_hash

      # @raise [Ksef::IntegrityError] when a published hash does not match the bytes
      # @return [self]
      def verify!
        return self unless verifiable? && !verified?

        raise IntegrityError,
              "The UPO fetched from #{source} does not match the hash the server published: " \
              "expected #{published_hash}, got #{sha256} over #{size} bytes. This is a corrupted " \
              "transfer, not a bad request — fetch it again. Do not archive these bytes as proof " \
              "of receipt (docs/REFERENCE.md §14.2)."
      end

      # Checks the document against the bundled schema — **a diagnostic, never a gate**
      # (§14.3). Archive the bytes regardless of what this says; see {Validator} for why
      # there is no raising counterpart.
      #
      # @return [Validation]
      def validate = Validator.validate(xml)

      # Writes the bytes untouched. Binary mode on purpose: this must not pick up a newline
      # translation or a re-encode on the way to disk, or the archived file stops matching
      # what the Ministry signed.
      #
      # @param path [String]
      # @return [Integer] bytes written
      def write(path)
        File.binwrite(path, xml)
      end

      # Deliberately not the document: a UPO is a few kilobytes of XML, and putting it in a
      # log line or an exception message helps nobody. DESIGN.md §4.5 forbids full invoice
      # payloads at default log level, and the same reasoning applies here.
      def to_s = "#<Ksef::UPO::Document #{size} bytes from #{source}>"

      def inspect
        state = verifiable? ? verified?.to_s : "unverifiable"
        "#<data Ksef::UPO::Document size=#{size} source=#{source.inspect} verified=#{state}>"
      end
    end
  end
end
