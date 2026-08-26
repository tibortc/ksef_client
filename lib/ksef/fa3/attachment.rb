# frozen_string_literal: true

module Ksef
  module FA3
    # The invoice attachment (`Zalacznik`), a top-level child of `Faktura`.
    #
    # It sits beside `Fa` rather than inside it, so it touches no summary and no arithmetic —
    # the whole node is descriptive. Two of the Ministry's worked examples carry one: an energy
    # bill's meter readings and tariff breakdown, which is exactly the kind of thing that used to
    # travel as a PDF beside the invoice.
    #
    # **Operational constraints are out of 0.1 scope on purpose** (DESIGN.md §7.4). Sending an
    # invoice that carries one requires prior opt-in in `e-Urząd Skarbowy` and, per
    # `docs/REFERENCE.md` §16, a batch session — and the size ceiling rises from 1 MB to 3 MB.
    # None of that is modelled here; this is the document, not the submission.
    Attachment = Data.define(:blocks)

    # Construction, invariants and serialisation for {Ksef::FA3::Attachment}.
    class Attachment
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      NEEDS_BLOCK = "An attachment needs at least one data block. `BlokDanych` is minOccurs=1 " \
                    "within `Zalacznik`, so an attachment without one cannot be serialised."

      # @param blocks [DataBlock, Array<DataBlock>] `BlokDanych`, 1..1000
      # @raise [Ksef::ValidationError] if it holds no block
      def initialize(blocks:)
        entries = Correction.wrap(blocks)
        raise ValidationError, NEEDS_BLOCK if entries.empty?

        super(blocks: entries.dup.freeze)
      end

      # An {Attachment}, or the blocks to make one from. The one-block case is the common one
      # and does not deserve two levels of ceremony; {Builder#attachment} is the caller.
      def self.wrap(value) = value.is_a?(Attachment) ? value : new(blocks: value)

      def to_fa3 = { "BlokDanych" => blocks.map(&:to_fa3) }
    end
  end
end
