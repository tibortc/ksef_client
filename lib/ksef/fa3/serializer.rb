# frozen_string_literal: true

require "nokogiri"

module Ksef
  module FA3
    # Writes an FA(3) document (DESIGN.md §7.5).
    #
    # Takes a nested structure keyed by **XSD element names** and emits XML. Element order
    # is never hand-written here: it comes from {Ksef::FA3::Generated::Types}, which is
    # derived from the pinned schema. KSeF rejects out-of-order elements, so ordering is a
    # correctness property, and the only way to keep it right through future schema
    # revisions is to regenerate rather than to maintain a list by hand (§7.1).
    #
    # Consequences of that design worth knowing:
    #
    #   - Keys the schema does not define at that position raise, rather than being
    #     silently dropped. A typo in an element name would otherwise produce a document
    #     that is missing a field and valid-looking.
    #   - The input order of the structure is irrelevant. Callers describe *what* the
    #     invoice contains; the schema decides where it goes.
    class Serializer
      NAMESPACE = "http://crd.gov.pl/wzor/2025/06/25/13775/"
      ROOT = "Faktura"

      # An element that carries attributes as well as text — KodFormularza is the only one
      # in FA(3), and both of its attributes are fixed by the schema.
      Element = Data.define(:text, :attributes) do
        def initialize(text: nil, attributes: {})
          super
        end
      end

      # @param content [Hash] nested, keyed by XSD element name
      def initialize(content)
        @content = content
      end

      # @return [String] UTF-8 XML with an explicit declaration
      def to_xml
        document = Nokogiri::XML::Document.new
        document.encoding = "UTF-8"

        root = document.create_element(ROOT)
        root.add_namespace_definition(nil, NAMESPACE)
        document.root = root

        write_children(document, root, ROOT, @content)
        qualify(root, root.namespace)

        document.to_xml(indent: 2)
      end

      private

      # `elementFormDefault="qualified"` means every element, not just the root, lives in
      # the target namespace (docs/REFERENCE.md §8). Nokogiri does not inherit a default
      # namespace onto nodes built with create_element, so it is applied on the way out.
      def qualify(node, namespace)
        node.namespace = namespace
        node.element_children.each { |child| qualify(child, namespace) }
      end

      def write_children(document, parent, type_key, values)
        return if values.nil?

        known = Generated::Types.ordered_elements(type_key)
        reject_unknown_keys(type_key, values, known)

        known.each do |particle|
          name = particle[:name]
          next unless values.key?(name)

          Array(wrap(values[name])).each do |value|
            parent.add_child(build_element(document, type_key, particle, value))
          end
        end
      end

      # A Hash is one nested element, not a list; anything else that is an Array is a
      # repeated element.
      def wrap(value) = value.is_a?(Array) ? value : [value]

      def build_element(document, type_key, particle, value)
        element = document.create_element(particle[:name])

        case value
        when Hash then write_children(document, element, child_type_key(type_key, particle), value)
        when Element then write_element_with_attributes(element, value)
        else element.content = value.to_s
        end

        element
      end

      def write_element_with_attributes(element, value)
        value.attributes.each { |name, attribute| element[name] = attribute.to_s }
        element.content = value.text.to_s unless value.text.nil?
      end

      # Named types are keyed by name, anonymous ones by path (§7.1).
      def child_type_key(parent_key, particle)
        named = particle[:type].to_s.sub(/\Atns:/, "")
        return named if Generated::Types[named]

        "#{parent_key}/#{particle[:name]}"
      end

      def reject_unknown_keys(type_key, values, known)
        unknown = values.keys.map(&:to_s) - known.map { |p| p[:name] }
        return if unknown.empty?

        raise ValidationError,
              "Unknown element(s) #{unknown.map(&:inspect).join(", ")} for #{type_key}. " \
              "Permitted here, in schema order: #{known.map { |p| p[:name] }.join(", ")}"
      end
    end
  end
end
