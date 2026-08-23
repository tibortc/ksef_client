# frozen_string_literal: true

# The pinned FA(3) sample corpus (docs/REFERENCE.md §1.4).
#
# `ksef-api` publishes no example invoice at all, so the samples come from two sibling CIRFMF
# repositories — `ksef-pdf-generator` and `ksef-client-csharp` — each pinned at its own
# commit. Everything here is upstream's bytes; nothing in this project wrote them, which is
# what makes them worth testing against.
module FA3Corpus
  DIR = File.expand_path("../fixtures/fa3", __dir__)

  # The C# samples are *templates*, not documents: they carry placeholders, and `#nip#` is
  # not a legal `TNrNIP`, so they would not even be XSD-valid as they stand. The pinned bytes
  # stay verbatim so their digests keep verifying, which is why substitution happens on read
  # rather than on disk. The pdf-generator sample needs none of this.
  PLACEHOLDERS = {
    "#nip#" => "9999999999",
    "#nipOdbiorca#" => "1111111111",
    "#invoice_number#" => "000001"
  }.freeze

  class << self
    # Every FA(3) invoice in the corpus, upstream's and ours, by path relative to {DIR}.
    def samples = Dir.glob("**/*.xml", base: DIR).sort

    # @return [String] the sample's XML, with placeholders substituted
    def read(relative)
      xml = File.read(File.join(DIR, relative), encoding: "UTF-8")
      PLACEHOLDERS.each { |placeholder, value| xml = xml.gsub(placeholder, value) }
      xml
    end
  end
end
