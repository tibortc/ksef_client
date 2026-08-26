# frozen_string_literal: true

module Ksef
  module FA3
    # One key/value pair inside an attachment (`MetaDane` on a data block, `TMetaDane` on a
    # table).
    #
    # Two elements, one shape: `ZKlucz`/`ZWartosc` and `TKlucz`/`TWartosc` differ only in the
    # names they are written under, which is why {#to_fa3} takes them rather than the class
    # coming in two copies.
    #
    # **Kept as an ordered list of pairs rather than a Hash**, wherever these are held. The
    # schema permits `MetaDane` to repeat up to a thousand times and says nothing about the keys
    # being distinct, so a Hash would silently drop a repeated key and reorder the rest — and an
    # attachment is a document a human reads, where order is the presentation. {DataBlock#to_h}
    # exists for callers who want the convenient view and can accept its losses.
    MetaEntry = Data.define(:key, :value)

    # Construction, invariants and serialisation for {Ksef::FA3::MetaEntry}.
    class MetaEntry
      # `#with` must re-run the constructor; on Ruby 3.2 it otherwise skips every invariant.
      include Canonical

      NEEDS_BOTH = "An attachment's metadata entry needs a key and a value. `ZKlucz` and " \
                   "`ZWartosc` are both mandatory within `MetaDane`."

      # @param key [String] `ZKlucz` / `TKlucz`, `TZnakowy` (256)
      # @param value [String] `ZWartosc` / `TWartosc`, `TZnakowy` (256)
      # @raise [Ksef::ValidationError] if either is absent
      def initialize(key:, value:)
        canonical = { key: Formatting.text(key), value: Formatting.text(value) }
        raise ValidationError, NEEDS_BOTH if canonical.values.any? { |v| v.nil? || v.empty? }

        super(**canonical)
      end

      # @param key_element [String] `"ZKlucz"` or `"TKlucz"`
      # @param value_element [String] `"ZWartosc"` or `"TWartosc"`
      def to_fa3(key_element:, value_element:)
        { key_element => key, value_element => value }
      end
    end
  end
end
