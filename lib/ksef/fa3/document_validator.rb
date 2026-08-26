# frozen_string_literal: true

module Ksef
  module FA3
    # Tier 1b — the admission rules KSeF applies to the **bytes**
    # (docs/REFERENCE.md §15.1, DESIGN.md §7.7 as amended 2026-08-24).
    #
    # These exist as a separate tier because of a shape problem that went unnoticed until the
    # rules were pinned. §7.7 described tier 1 as a *model* tier — required fields, enums,
    # checksums, dates — and four of the six rules KSeF actually applies are properties of the
    # serialized document: a byte-order mark, the prolog's declared encoding, processing
    # instructions, and discouraged Unicode characters. At model time there is no document, so
    # a model tier structurally cannot see any of them.
    #
    # **And tier 2 cannot see them either**, which is the whole justification. Upstream ships
    # `invoice-template-fa-3-with-disallowed-unicode-characters.xml`, which carries U+0087 and
    # U+009B and is XSD-valid against the pinned schema **once its `#nip#` placeholders are
    # substituted** — which `spec/support/fa3_corpus.rb` does on read, the pinned bytes staying
    # verbatim so their digests keep verifying. A schema-only client sends that invoice and
    # KSeF rejects it.
    #
    # Runs on `#to_xml`'s output, and must run before those bytes are hashed and encrypted —
    # after that point a rejection costs a round trip and a session.
    module DocumentValidator
      # `EF BB BF`. Legal Unicode, legal XML, and an outright rejection here.
      BOM = "\xEF\xBB\xBF"

      # Only the encoding matters, and only when a prolog is present at all — the prolog is
      # optional, but if it declares anything other than UTF-8 the document is refused.
      PROLOG = /\A<\?xml\s[^>]*\?>/
      PROLOG_ENCODING = /encoding\s*=\s*["']([^"']+)["']/

      # A processing instruction, excluding the XML declaration — which is not a PI, though it
      # looks like one. Anchoring on a name that is not `xml` is what separates them.
      #
      # The target is an XML `Name`, which may contain non-ASCII letters, so it cannot be
      # matched with `\w`: `<?źdźbło x?>` is a real processing instruction that an ASCII-only
      # class waved through — the one input a review on 2026-08-24 found that every tier passed
      # while §15.1 says KSeF rejects it.
      PROCESSING_INSTRUCTION = /<\?(?!xml[\s?])([^\s?>]+)/

      # Stripped before the search above, because `<?php ... ?>` written inside a comment or a
      # CDATA section is text, not a processing instruction, and rejecting it would refuse an
      # admissible document. Characters are *not* scanned this way: a discouraged character is
      # forbidden wherever it appears, comments included.
      NON_MARKUP = /<!--.*?-->|<!\[CDATA\[.*?\]\]>/m

      # §15.1's discouraged characters, exactly as the pinned document lists them. Note U+0085
      # sits between the first two ranges and is *not* forbidden, and that the plane
      # noncharacters start at plane 1 — plane 0's U+FFFE/U+FFFF are excluded from XML's `Char`
      # production already, so they cannot occur in a well-formed document.
      DISCOURAGED = [
        0x7F..0x84,
        0x86..0x9F,
        0xFDD0..0xFDEF,
        *(1..16).map { |plane| ((plane << 16) | 0xFFFE)..((plane << 16) | 0xFFFF) }
      ].freeze

      # 1 000 000 bytes, and upstream means the decimal million rather than 2^20 — it writes
      # "1 MB * (1 000 000 bajtów)" (§15.5). Attachments raise it to 3 MB and are batch-only,
      # so 0.1 has no reason to carry the larger figure.
      # It is a **default, not a ceiling of the format.** Upstream marks the figure with an
      # asterisk — *"Jeżeli w scenariuszach biznesowych organizacji dostępne limity są
      # niewystarczające, prosimy o kontakt z działem wsparcia KSeF"* — and `limity.md` heads the
      # same numbers *"Wartość domyślna"*, with `GET /limits/context` returning the live values
      # for a context. So an organisation that has negotiated a higher limit passes its own via
      # `max_bytes:`; hard-coding this as absolute rejected invoices KSeF would have accepted.
      MAX_BYTES = 1_000_000

      # {DISCOURAGED} compiled into one character class.
      DISCOURAGED_PATTERN = Regexp.new(
        "[#{DISCOURAGED.map { |range| "\\u{#{range.first.to_s(16)}}-\\u{#{range.last.to_s(16)}}" }.join}]"
      ).freeze

      class << self
        # @param xml [String] a serialized FA(3) document
        # @param max_bytes [Integer] the size ceiling for this context; see {MAX_BYTES}
        # @return [Array<Issue>] empty when KSeF would admit these bytes
        # @param xml [String] the serialised document; anything else is reported rather than
        #   raising `NoMethodError`, since this tier's whole job is to answer about bytes
        def errors_for(xml, max_bytes: MAX_BYTES)
          xml = xml.to_s
          # Everything below reads the string as text, and every one of those reads raises on
          # invalid bytes rather than reporting them. It is also a rule in its own right: §15.1
          # requires the document to *be* UTF-8, not merely to lack a byte-order mark.
          return [encoding_issue] unless FieldChecks.utf8?(xml)

          [bom_issue(xml), prolog_issue(xml), *instruction_issues(xml),
           *character_issues(xml), size_issue(xml, max_bytes)].compact
        end

        def valid?(xml, max_bytes: MAX_BYTES) = errors_for(xml, max_bytes: max_bytes).empty?

        private

        def encoding_issue
          Issue.new(field: "document",
                    message: "is not valid UTF-8; KSeF requires UTF-8 encoding without a " \
                             "byte-order mark (docs/REFERENCE.md §15.1)")
        end

        def bom_issue(xml)
          return nil unless xml.b.start_with?(BOM.b)

          Issue.new(field: "document",
                    message: "starts with a UTF-8 byte-order mark; KSeF requires UTF-8 without one")
        end

        def prolog_issue(xml)
          prolog = xml[PROLOG]
          return nil if prolog.nil?

          declared = prolog[PROLOG_ENCODING, 1]
          return nil if declared.nil? || declared.casecmp?("UTF-8")

          Issue.new(field: "document",
                    message: "declares encoding #{declared.inspect} in its prolog; only UTF-8 is accepted")
        end

        def instruction_issues(xml)
          xml.gsub(NON_MARKUP, "").scan(PROCESSING_INSTRUCTION).flatten.uniq.map do |target|
            Issue.new(field: "document",
                      message: "contains the processing instruction <?#{target}…?>; KSeF accepts none")
          end
        end

        # Scans the characters rather than the parsed tree: these are forbidden wherever they
        # appear, including inside attribute values. Numeric character references are not
        # sought, because {Serializer} escapes every `&` it writes, so a reference cannot
        # survive into output this method is given.
        def character_issues(xml)
          # One regexp pass rather than a per-character range walk. The walk cost about 1.2s on
          # a legal 500 KB invoice — some eighty times the whole XSD validation — and this runs
          # on every default `send_invoice`.
          found = xml.scan(DISCOURAGED_PATTERN).uniq
          return [] if found.empty?

          found.map do |char|
            Issue.new(field: "document",
                      message: format("contains U+%04X, a character XML 1.0 discourages and " \
                                      "KSeF refuses (docs/REFERENCE.md §15.1)", char.ord))
          end
        end

        # Measured in **bytes**: upstream writes "1 MB * (1 000 000 bajtów)", and a document of
        # Polish text is far longer in bytes than in characters. The boundary is inclusive —
        # "maksymalny rozmiar" — so exactly the limit is accepted.
        def size_issue(xml, max_bytes)
          size = xml.bytesize
          return nil if size <= max_bytes

          Issue.new(field: "document",
                    message: "is #{size} bytes; KSeF accepts #{max_bytes} without an attachment")
        end
      end
    end
  end
end
