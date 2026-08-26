# frozen_string_literal: true

module Ksef
  module FA3
    # Routes `Data#with` back through the constructor, so a copy is subject to the same
    # invariants as an original.
    #
    # ## Why this is not redundant
    #
    # **`Data#with` does not call a custom `initialize` on Ruby 3.2** — it does on 4.0, and 3.2
    # is this gem's declared floor (DESIGN.md §3). Measured on 3.2.11 and 4.0.6, 2026-08-24:
    #
    #     invoice.with(rounding: :junk)
    #     # 4.0.6  => Ksef::ValidationError
    #     # 3.2.11 => an Invoice whose rounding is :junk
    #
    # Every "canonicalise on the way in" rule of docs/REFERENCE.md §8.2b was therefore
    # skippable through a public method on the floor the gem promises to support — including
    # the ban on `Float` in monetary fields, which is a hard rule:
    # `line.with(quantity: 0.1)` stored a Float on 3.2 and raised on 4.0.
    #
    # RuboCop cannot see this: it is a semantic difference between versions, not a missing
    # method, so `TargetRubyVersion` says nothing about it. Only running on 3.2 finds it, and
    # nothing did, because no spec exercised `#with` at all.
    #
    # Defining `#with` explicitly makes the two versions agree and makes the invariants
    # actually invariant. Do not remove it when 3.2 is eventually dropped without checking
    # that every constructor here is side-effect free — `#with` going through `new` is now
    # load-bearing for correctness, not just for portability.
    module Canonical
      # **`members`, not `to_h`.** {Provenance#to_h} redacts `raw_document` so that logging or
      # `JSON.dump`ing an invoice does not embed its entire source; rebuilding from that
      # redacted Hash silently dropped the retained document on every copy, taking
      # `#unmapped_elements` and `#source_errors` with it. Reading the members directly keeps
      # `#with` a copy rather than a partial one.
      #
      # @param changes [Hash] members to replace
      # @return [Data] a new instance, constructed and therefore validated
      def with(**changes)
        self.class.new(**self.class.members.to_h { |name| [name, public_send(name)] }, **changes)
      end
    end
  end
end
