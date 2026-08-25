# frozen_string_literal: true

module Ksef
  # The FA(3) invoice builder. Has no HTTP dependency and is usable on its own
  # (DESIGN.md §5.1) — the transport layer accepts anything responding to `#to_xml`.
  module FA3
    class << self
      # Build an {Invoice} through the keyword DSL of DESIGN.md §8.
      #
      # The DSL is a thin, forgiving front end over the value objects: it accepts English
      # shorthand (`qty:`, `vat:`), coerces a plain Hash into an {Address}, and reports a
      # missing or misspelled field by name instead of letting it surface later as a
      # schema rejection. Everything it produces could be constructed by hand; see the
      # README for the same invoice written the long way.
      #
      # @example
      #   invoice = Ksef::FA3.build do |f|
      #     f.seller nip: "9999999999", name: "ACME sp. z o.o.",
      #              address: { street: "Prosta 1", city: "Warszawa", postal_code: "00-001" }
      #     f.buyer  nip: "1111111111", name: "Klient S.A.", address: "Długa 2, 30-001 Kraków"
      #     f.number "FV/2026/08/001"
      #     f.issue_date Date.today
      #     f.line name: "Consulting", qty: 10, unit: "godz.", net_unit_price: 150, vat: "23"
      #   end
      #
      # @yieldparam builder [Builder]
      # @return [Invoice]
      # @raise [Ksef::ValidationError] if a required field is missing or a key is unknown
      def build
        raise ArgumentError, "Ksef::FA3.build requires a block; see DESIGN.md §8" unless block_given?

        builder = Builder.new
        yield builder
        builder.to_invoice
      end

      # Read an FA(3) document back into an {Invoice} (DESIGN.md §7.6).
      #
      # The inverse of {#build} only as far as this model reaches. FA(3) is much larger than
      # a plain `VAT` invoice, so the whole document is retained on
      # {Invoice#raw_document} and {Invoice#unmapped_elements} names what `#to_xml` would
      # drop. Check it before re-serialising anything you did not write yourself.
      #
      # @example round-tripping your own invoice
      #   Ksef::FA3.parse(invoice.to_xml) == invoice   # => true
      #
      # @example reading one KSeF sent back
      #   parsed = Ksef::FA3.parse(client.download_invoice("5265877635-20250826-0100001AF629-AF"))
      #   parsed.number                                # => "FA/2026/08/001"
      #   parsed.unmapped_elements                     # => ["Faktura/Podmiot3", …]
      #
      # @param xml [String, Nokogiri::XML::Document]
      # @return [Invoice]
      # @raise [Ksef::ValidationError] if the input is not a parseable FA(3) invoice, or
      #   identifies a party by something other than a NIP
      def parse(xml) = Parser.parse(xml)
    end
  end
end
