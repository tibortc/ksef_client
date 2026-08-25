# frozen_string_literal: true

module Ksef
  module FA3
    # Reads an XML element's subtree into the nested-Hash shape {Serializer} consumes.
    #
    # A leaf becomes its text, a parent becomes a Hash, and a name that repeats becomes an
    # Array — which is exactly the shape {Serializer} writes back, so a subtree read this way
    # round-trips without the model having to understand any of it.
    #
    # {Parser} uses it for `Adnotacje`, a group of eight annotations with real tax
    # consequences and far too much structure to model field by field in 0.1. Reading it
    # structurally is what stops re-serialisation from silently resetting a declaration the
    # document made (see {Invoice::DEFAULT_ANNOTATIONS}).
    #
    # It carries no FA(3) knowledge, which is why it lives apart from the parser.
    module ElementTree
      class << self
        # @param node [Nokogiri::XML::Node, nil]
        # @return [Hash, nil] nil when the node is absent, so a caller's default can apply
        def to_hash(node)
          return nil if node.nil?

          node.element_children.each_with_object({}) do |child, acc|
            store(acc, child.name, value_of(child))
          end
        end

        private

        def value_of(child)
          child.element_children.empty? ? child.text : to_hash(child)
        end

        # `Array()` is deliberately avoided: it splats a Hash into an array of pairs, which
        # would quietly mangle a repeated parent element into nonsense.
        def store(acc, name, value)
          unless acc.key?(name)
            acc[name] = value
            return
          end

          existing = acc[name]
          acc[name] = existing.is_a?(Array) ? existing + [value] : [existing, value]
        end
      end
    end
  end
end
