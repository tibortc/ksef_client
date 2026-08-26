# frozen_string_literal: true

module Ksef
  module FA3
    # One block of an invoice attachment (`BlokDanych`).
    #
    # An attachment is a *structured* document rather than a file: FA(3) carries no bytes and no
    # MIME type, only headings, key/value metadata, paragraphs and tables. That is what makes it
    # expressible in the model at all, and it is why DESIGN.md §7.4 asks for it "at build/parse
    # level" while putting the operational side of attachments out of 0.1 scope.
    #
    # **`MetaDane` is mandatory.** It is the one child of `BlokDanych` the schema requires, so a
    # block describing itself only with a heading or a table is not a document KSeF accepts —
    # which is worth refusing at construction rather than at serialisation.
    DataBlock = Data.define(:metadata, :heading, :paragraphs, :tables)

    # Construction, invariants and serialisation for {Ksef::FA3::DataBlock}.
    class DataBlock
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      NEEDS_METADATA = "An attachment data block needs at least one metadata entry. " \
                       "`MetaDane` is minOccurs=1 within `BlokDanych`."
      TOO_MANY_PARAGRAPHS = "`Tekst` holds at most 10 `Akapit` paragraphs."

      # `Akapit` is `maxOccurs="10"`, and the ceiling is low enough to hit by accident.
      MAX_PARAGRAPHS = 10

      # @param metadata [Hash{String=>String}, MetaEntry, Array<MetaEntry>] `MetaDane`, 1..1000.
      #   A Hash is accepted for convenience and converted to ordered pairs; see {MetaEntry} for
      #   why the pairs are what gets stored.
      # @param heading [String, nil] `ZNaglowek`, `TZnakowy512`
      # @param paragraphs [String, Array<String>] `Tekst/Akapit`, at most 10
      # @param tables [AttachmentTable, Array<AttachmentTable>] `Tabela`, 0..1000
      # @raise [Ksef::ValidationError] if it states no metadata, or too many paragraphs
      def initialize(metadata:, heading: nil, paragraphs: [], tables: [])
        entries = self.class.entries(metadata)
        text = self.class.paragraphs_from(paragraphs)
        raise ValidationError, NEEDS_METADATA if entries.empty?
        raise ValidationError, TOO_MANY_PARAGRAPHS if text.size > MAX_PARAGRAPHS

        super(metadata: entries.dup.freeze, heading: Formatting.text(heading),
              paragraphs: text, tables: Correction.wrap(tables).dup.freeze)
      end

      # `compact`, because a nil paragraph is nothing rather than an empty one — unlike a table
      # cell, where nil becomes `""` to keep the row's width. Paragraphs have no positional
      # pairing to preserve, so dropping one loses nothing.
      def self.paragraphs_from(paragraphs)
        Correction.wrap(paragraphs).map { |paragraph| Formatting.text(paragraph) }.compact.freeze
      end

      # Accepts the ergonomic form and the faithful one. A Hash cannot express a repeated key,
      # which the schema permits — so it is sugar for building, never what parsing produces.
      def self.entries(metadata)
        return metadata.map { |key, value| MetaEntry.new(key: key, value: value) } if metadata.is_a?(Hash)

        Correction.wrap(metadata)
      end

      # @return [Hash{String=>String}] the metadata as a Hash. **Lossy** where a key repeats;
      #   read {#metadata} when that matters.
      def to_h_metadata = metadata.to_h { |entry| [entry.key, entry.value] }

      def to_fa3
        {
          "ZNaglowek" => heading,
          "MetaDane" => metadata.map { |e| e.to_fa3(key_element: "ZKlucz", value_element: "ZWartosc") },
          "Tekst" => paragraphs.empty? ? nil : { "Akapit" => paragraphs },
          "Tabela" => tables.map(&:to_fa3)
        }.compact
      end
    end
  end
end
