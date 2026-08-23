# frozen_string_literal: true

require "nokogiri"

module Ksef
  module FA3
    # Everything about the document an {Invoice} was read from, for invoices that were read
    # rather than built.
    #
    # Mixed into {Invoice}, and separate from it because it answers a different question.
    # {Invoice} is an invoice; this is the paper trail — where these fields came from, whether
    # anything was left behind, and how the pair should behave when compared or printed.
    #
    # The including class must define an `IDENTITY` constant listing the members that make up
    # its identity, i.e. all of them except `raw_document`.
    module Provenance
      # `raw_document` is provenance, not identity. Two invoices with the same seller, buyer,
      # number, dates and lines are the same invoice whether they were built here or read back
      # from XML — so it takes no part in equality. Without that,
      # `parse(invoice.to_xml) == invoice` could never hold and DESIGN.md §7.6's round-trip
      # law would be unstatable in the form it is written.
      #
      # `is_a?` rather than a class equality check, so a future subtype comparing equal to its
      # parent stays possible.
      def ==(other)
        other.is_a?(self.class) && identity_fields.all? { |field| public_send(field) == other.public_send(field) }
      end
      alias eql? ==

      def hash = identity_values.hash

      # `Data#inspect` would dump the entire XML document into any console line or error
      # message that mentions an invoice — including RSpec diffs. Redacted for the same
      # reason {Ksef::Sessions::InvoiceState#inspect} redacts its download URL: an accidental
      # `p invoice` should stay readable.
      def inspect
        fields = identity_fields.map { |field| "#{field}=#{public_send(field).inspect}" }
        fields << "raw_document=#{raw_document ? "#<Nokogiri::XML::Document (retained)>" : "nil"}"
        "#<data #{self.class.name} #{fields.join(", ")}>"
      end
      alias to_s inspect

      # Element paths present in {#raw_document} but absent from this model's own
      # serialisation — that is, exactly what `#to_xml` would drop.
      #
      # Computed by difference rather than from a hand-maintained list of mapped fields, so it
      # cannot drift away from what {Serializer} actually writes. Repeated elements collapse
      # to one path: the question it answers is *which kinds* of element are lost, not how
      # many times.
      #
      # It serialises the invoice to find out, so it is a diagnostic to reach for when
      # deciding whether re-serialising a foreign document is safe — not a loop body.
      #
      # @return [Array<String>] slash-separated local-name paths, sorted; empty when this
      #   invoice was built rather than parsed
      def unmapped_elements
        return [] if raw_document.nil?

        (element_paths(raw_document) - element_paths(Nokogiri::XML(to_xml))).sort
      end

      # @return [Boolean] whether `#to_xml` reproduces every element the source document had
      def fully_mapped? = unmapped_elements.empty?

      private

      def identity_fields = self.class::IDENTITY

      def identity_values = identity_fields.map { |field| public_send(field) }

      # `Nokogiri::XML::Node#path` is no help here: for a document whose elements sit in a
      # default namespace it renders every step as `*`, so all five levels of an invoice come
      # back as `/*`, `/*/*`, … Local names have to be walked by hand.
      def element_paths(document)
        document.xpath("//*").map do |node|
          names = [node.name]
          parent = node.parent
          # No safe navigation: these nodes come from `//*`, so the walk always terminates at
          # the document, whose `element?` is false. A `&.` would add an unreachable branch.
          while parent.element?
            names.unshift(parent.name)
            parent = parent.parent
          end
          names.join("/")
        end.uniq
      end
    end
  end
end
