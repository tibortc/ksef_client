# frozen_string_literal: true

module Ksef
  module FA3
    # One column of an attachment table (`Kol`): a heading, and the kind of value the column
    # holds.
    #
    # `Typ` is FA(3)'s **only** attribute carrying an inline enumeration, and the permitted
    # values are read from the generated metadata rather than restated here — DESIGN.md §7.1.
    # Until 2026-08-26 the codegen dropped inline attribute enumerations entirely, so this class
    # could not have been written without a hand-typed constant; `docs/REFERENCE.md` §18.2
    # records why that mattered enough to fix first.
    TableColumn = Data.define(:name, :type)

    # Construction, invariants and serialisation for {Ksef::FA3::TableColumn}.
    class TableColumn
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      # @return [Array<String>] `date`, `datetime`, `dec`, `int`, `time`, `txt`
      def self.types
        Generated::Types::ALL
          .fetch("Faktura/Zalacznik/BlokDanych/Tabela/TNaglowek/Kol")[:attributes]
          .find { |attribute| attribute[:name] == "Typ" }
          .fetch(:values)
      end

      # @param name [String] `NKom`, the column heading. `TZnakowy2` permits an empty one, and
      #   a table whose first column labels the rows often has exactly that.
      # @param type [String] `Typ`, required by the schema — there is no default, because a
      #   column's kind is a statement about its cells and guessing `txt` would make one.
      # @raise [Ksef::ValidationError] if the type is not one the schema permits
      def initialize(name:, type:)
        canonical = Formatting.text(type)
        unless self.class.types.include?(canonical)
          raise ValidationError,
                "Column type #{type.inspect} is not one FA(3) permits. `Kol/@Typ` allows " \
                "#{self.class.types.join(", ")}."
        end

        super(name: Formatting.text(name).to_s, type: canonical)
      end

      def to_fa3
        Serializer::Element.new(text: nil, attributes: { "Typ" => type }, children: { "NKom" => name })
      end
    end
  end
end
