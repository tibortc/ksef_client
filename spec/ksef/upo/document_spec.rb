# frozen_string_literal: true

require "tmpdir"

RSpec.describe Ksef::UPO::Document do
  subject(:document) { described_class.new(xml: xml, published_hash: hash_of(xml), source: :storage) }

  # A real pinned UPO, so the byte-for-byte guarantees below are tested against a document
  # of the shape and size actually received — Polish characters, XAdES signature and all.
  let(:xml) do
    File.read(
      File.expand_path("../../fixtures/upo/upo-faktura-kontekst-id-nip.xml", __dir__),
      encoding: "UTF-8"
    )
  end

  def hash_of(bytes) = Ksef::Crypto::Digest.of(bytes).base64

  describe "the verbatim guarantee" do
    # The Ministry's XAdES signature covers octets, not an abstract tree, so anything that
    # re-serialises the document risks producing one that no longer verifies (§12).
    it "holds the exact bytes it was given" do
      expect(document.xml).to equal(xml)
      expect(document.size).to eq(xml.bytesize)
    end

    it "measures bytes, not characters — a UPO is full of Polish text" do
      expect(xml.bytesize).to be > xml.size
      expect(document.size).to eq(xml.bytesize)
    end

    it "writes the bytes to disk untouched" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "upo.xml")
        document.write(path)

        expect(File.binread(path)).to eq(xml.dup.force_encoding(Encoding::BINARY))
        expect(hash_of(File.binread(path))).to eq(document.sha256)
      end
    end

    it "offers no parsed form that could be re-serialised by accident" do
      expect(document).not_to respond_to(:document, :to_xml, :parse)
    end
  end

  describe "#verified?" do
    it "is true when the published hash matches" do
      expect(document.verified?).to be(true)
    end

    it "is false when it does not" do
      tampered = described_class.new(xml: "#{xml} ", published_hash: hash_of(xml), source: :storage)

      expect(tampered.verified?).to be(false)
    end

    # The metered API route publishes no hash. #verified? is false there too, so the
    # distinction lives in #verifiable? — conflating the two would make every fetch by that
    # route look tampered with.
    it "is false but unverifiable when no hash was published" do
      unverifiable = described_class.new(xml: xml, published_hash: nil, source: :api)

      expect(unverifiable.verifiable?).to be(false)
      expect(unverifiable.verified?).to be(false)
    end

    it "is verifiable when a hash was published" do
      expect(document.verifiable?).to be(true)
    end
  end

  describe "#verify!" do
    it "returns itself when the hash matches" do
      expect(document.verify!).to equal(document)
    end

    it "returns itself when there is no hash to check against" do
      unverifiable = described_class.new(xml: xml, published_hash: nil, source: :api)

      expect(unverifiable.verify!).to equal(unverifiable)
    end

    # A single trailing space is enough — which is the point of checking at all.
    it "raises on a mismatch, and says not to archive the bytes" do
      tampered = described_class.new(xml: "#{xml} ", published_hash: hash_of(xml), source: :storage)

      expect { tampered.verify! }
        .to raise_error(Ksef::IntegrityError, /Do not archive these bytes as proof of receipt/)
    end

    it "names both hashes and the byte count, so the failure is diagnosable" do
      tampered = described_class.new(xml: "x", published_hash: hash_of(xml), source: :storage)

      expect { tampered.verify! }
        .to raise_error(Ksef::IntegrityError, /expected #{Regexp.escape(hash_of(xml))}.*over 1 bytes/m)
    end
  end

  # DESIGN.md §4.5 forbids full invoice payloads at default log level, and a UPO is the same
  # kind of thing: kilobytes of XML that help nobody in a log line.
  describe "not leaking the document into logs" do
    it "summarises rather than dumping in #to_s" do
      expect(document.to_s).to eq("#<Ksef::UPO::Document #{xml.bytesize} bytes from storage>")
      expect("upo=#{document}").not_to include("Potwierdzenie")
    end

    it "says unverifiable in #inspect rather than claiming a verdict" do
      unverifiable = described_class.new(xml: xml, published_hash: nil, source: :api)

      expect(unverifiable.inspect).to include("verified=unverifiable")
    end

    it "reports size, source and verification state in #inspect, but not the XML" do
      expect(document.inspect).to include("source=:storage", "verified=true")
      expect(document.inspect).not_to include("Potwierdzenie")
    end
  end

  it "computes the same digest form the x-ms-meta-hash header uses" do
    expect(document.sha256).to eq(document.published_hash)
    expect(document.sha256.length).to eq(44)
  end
end
