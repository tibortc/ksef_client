# frozen_string_literal: true

module Ksef
  module FA3
    # Reading named elements out of an FA(3) document.
    #
    # FA(3) sets `elementFormDefault="qualified"`, so **every** element sits in the target
    # namespace, not just the root — and unprefixed XPath therefore matches nothing at all.
    # One prefix is bound once here, and {#qualify} applies it to every step of a path, so
    # callers write `"Naglowek/DataWytworzeniaFa"` instead of interpolating a prefix per step
    # and getting it wrong on the second one.
    #
    # Separate from {Parser} because none of it knows anything about invoices.
    module NodeReader
      PREFIX = "fa"
      NAMESPACES = { PREFIX => Serializer::NAMESPACE }.freeze

      private

      # @param path [String] slash-separated local names, e.g. `"Naglowek/DataWytworzeniaFa"`
      def qualify(path) = path.split("/").map { |step| "#{PREFIX}:#{step}" }.join("/")

      def element(node, path) = node.at_xpath(qualify(path), NAMESPACES)

      def elements(node, path) = node.xpath(qualify(path), NAMESPACES)

      def text(node, path) = element(node, path)&.text

      def text!(node, path)
        text(node, path) || raise(ValidationError, "#{label(node)} is missing the mandatory <#{path}> element")
      end

      def require_element(node, name, context:)
        found = element(node, name)
        return found if found

        raise ValidationError, "#{context} is missing the mandatory <#{name}> element"
      end

      # `DaneIdentyfikacyjne` appears under both subjects, so the bare element name would not
      # tell a caller which one is wrong. One level of parent disambiguates every element read
      # here; every call site passes a nested element, so there is always a parent.
      def label(node) = "#{node.parent.name}/#{node.name}"
    end
  end
end
