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

  # The Ministry's own worked examples, redistributed under the terms recorded in
  # `mf-samples/NOTICE.md` and ledgered at docs/REFERENCE.md §1.5. Twenty-six invoices covering
  # **all seven** `RodzajFaktury` values — the only corpus of non-`VAT` types that exists, since
  # no CIRFMF repository contains one.
  #
  # Listed as a count rather than by name: they are `przyklad-01` … `przyklad-26`, and a gap
  # would mean a missing pin rather than a deliberate omission.
  MINISTRY_COUNT = 26

  # **Twenty-two of the twenty-six**, as of 2026-08-26 — every sample of every one of the seven
  # `RodzajFaktury` values except four, and those four are refused for a *construct* rather
  # than for their type:
  #
  # - `08`, `19` — **gross-priced rows** (`P_9B`/`P_11A` under art. 106e ust. 7-8) where this
  #   model carries net pricing only.
  # - `22`, `23` — a buyer identified by `NrVatUE` and by `NrID`, where {Subject} holds a NIP
  #   only (§8.2a).
  #
  # Derived rather than listed: with every type modelled, "everything but those four" is the
  # honest statement, and a list would go stale silently the next time one is unblocked.
  MINISTRY_MODELLED = ((1..26).map { |n| format("mf-samples/przyklad-%02d.xml", n) } -
                       %w[08 19 22 23].map { |n| "mf-samples/przyklad-#{n}.xml" }).freeze

  # Samples with no `FaWiersz` at all, which is legal — `minOccurs="0"` — and is how the
  # Ministry writes a correction of buyer data or a collective discount. Listed so the
  # "modelled samples have lines" assertion can exempt exactly these rather than being
  # weakened for all twelve (§8.4).
  # A `ZAL` and its corrections join them for a different reason: `Zamowienie`'s positions take
  # the place of `FaWiersz` entirely (§8.5).
  MINISTRY_WITHOUT_LINES = %w[
    mf-samples/przyklad-05.xml
    mf-samples/przyklad-06.xml
    mf-samples/przyklad-10.xml
    mf-samples/przyklad-11.xml
    mf-samples/przyklad-12.xml
    mf-samples/przyklad-13.xml
  ].freeze

  # Valid FA(3), beyond this model, and refused with a message that says so.
  MINISTRY_BEYOND_MODEL = {
    "mf-samples/przyklad-08.xml" => /priced gross/,
    "mf-samples/przyklad-19.xml" => /priced gross/,
    "mf-samples/przyklad-22.xml" => /identified by KodUE, NrVatUE/,
    "mf-samples/przyklad-23.xml" => /identified by KodKraju, NrID/
  }.freeze

  # **Empty, and measured to be.** Every `RodzajFaktury` the schema defines is modelled, so
  # nothing is refused by type any more. Kept as a constant rather than deleted: the round-trip
  # spec parses all twenty-six and collects the ones refused *for their type*, then asserts the
  # result equals this — so re-introducing a type-level refusal without saying so here fails.
  #
  # It previously asserted `be_empty` against this literal, which is a statement about the
  # constant and not about the parser: removing `UPR` from `Parser::SUPPORTED_TYPES` left that
  # example passing.
  MINISTRY_UNSUPPORTED_TYPES = [].freeze

  # This gem's own *serializer output*, which is fully within the model and so round-trips byte
  # for byte. `minimal_vat_invoice.xml` is deliberately absent: it is hand-written for
  # `validator_spec`, and writes `<P_8B>10.00</P_8B>` where {Ksef::FA3::Formatting.quantity}
  # emits `10` — both legal `TIlosci`, numerically identical, so it belongs to the
  # XSD-validity set and not to the byte-exact one.
  OURS = %w[
    golden/vat_single_line.xml
    golden/kor_before_after.xml
    golden/zal_order.xml
    golden/roz_settlement.xml
    golden/upr_simplified.xml
    golden/kor_zal_order.xml
  ].freeze

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

    # @return [Array<String>] all twenty-six Ministry samples, verified present
    # @raise [RuntimeError] if the count is short, which means a pin went missing
    def ministry
      found = Dir.glob("mf-samples/przyklad-*.xml", base: DIR).sort
      unless found.size == MINISTRY_COUNT
        raise "Expected #{MINISTRY_COUNT} Ministry samples in #{DIR}/mf-samples, found #{found.size}"
      end

      found
    end

    # The `RodzajFaktury` a sample declares, read from the document rather than from a table
    # here — a table would be one more thing to keep in step with the pinned bytes.
    def invoice_type(relative)
      Nokogiri::XML(read(relative)).remove_namespaces!.at_xpath("//Fa/RodzajFaktury")&.text
    end

    # @return [String] the absolute path of a sample, for the few cases wanting the bytes
    #   exactly as they are on disk rather than {read}'s substituted form
    def path(relative) = File.join(DIR, relative)

    # @return [String] the sample's XML, with placeholders substituted
    def read(relative)
      xml = File.read(File.join(DIR, relative), encoding: "UTF-8")
      PLACEHOLDERS.each { |placeholder, value| xml = xml.gsub(placeholder, value) }
      xml
    end
  end
end
