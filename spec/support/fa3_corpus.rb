# frozen_string_literal: true

# The pinned FA(3) sample corpus (docs/REFERENCE.md §1.4), plus this project's own goldens.
#
# `ksef-api` publishes no example invoice at all, so the upstream samples come from two sibling
# CIRFMF repositories — `ksef-pdf-generator` and `ksef-client-csharp` — each pinned at its own
# commit. Those four are bytes nobody in this project wrote, which is what makes them worth
# testing against.
#
# **{UPSTREAM} is listed explicitly, not globbed.** A glob is silent when it matches nothing:
# a typo in the directory, the pattern or the `base:` keyword would have removed 24 examples
# from the round-trip suite and left it green, with coverage unchanged and `rake` still exiting
# 0. The digests in `docs/artifacts.sha256` protect the files' *contents*; nothing protected
# the wiring that finds them. {.upstream} now fails loudly instead.
module FA3Corpus
  DIR = File.expand_path("../fixtures/fa3", __dir__)

  # Upstream's samples, by path relative to {DIR}. Adding one here is deliberate; see §1.4.
  UPSTREAM = %w[
    ksef-client-csharp/invoice-template-fa-3.xml
    ksef-client-csharp/invoice-template-fa-3-with-custom-Subject3.xml
    ksef-client-csharp/invoice-template-fa-3-with-disallowed-unicode-characters.xml
    ksef-pdf-generator/invoice.xml
  ].freeze

  # This gem's own *serializer output*, which is fully within the model and so round-trips byte
  # for byte. `minimal_vat_invoice.xml` is deliberately absent: it is hand-written for
  # `validator_spec`, and writes `<P_8B>10.00</P_8B>` where {Ksef::FA3::Formatting.quantity}
  # emits `10` — both legal `TIlosci`, numerically identical, so it belongs to the
  # XSD-validity set and not to the byte-exact one.
  OURS = %w[golden/vat_single_line.xml].freeze

  # The C# samples are *templates*, not documents: they carry placeholders, and `#nip#` is not
  # a legal `TNrNIP`, so they are not even XSD-valid as they stand. The pinned bytes stay
  # verbatim so their digests keep verifying, which is why substitution happens on read rather
  # than on disk. The pdf-generator sample needs none of this.
  PLACEHOLDERS = {
    "#nip#" => "9999999999",
    "#nipOdbiorca#" => "1111111111",
    "#invoice_number#" => "000001"
  }.freeze

  class << self
    # @return [Array<String>] {UPSTREAM}, verified present
    # @raise [RuntimeError] if a pinned sample is missing, rather than quietly testing nothing
    def upstream
      missing = UPSTREAM.reject { |relative| File.exist?(File.join(DIR, relative)) }
      raise "Pinned FA(3) samples missing from #{DIR}: #{missing.join(", ")}" unless missing.empty?

      UPSTREAM
    end

    def ours = OURS

    # @return [String] the sample's XML, with placeholders substituted
    def read(relative)
      xml = File.read(File.join(DIR, relative), encoding: "UTF-8")
      PLACEHOLDERS.each { |placeholder, value| xml = xml.gsub(placeholder, value) }
      xml
    end
  end
end
