# frozen_string_literal: true

module Ksef
  module FA3
    # One validation complaint, addressed to the field that caused it.
    #
    # DESIGN.md §7.7 asks tier 1 for "field-addressed errors", and this is why: a caller
    # mapping an invoice back to a form, a CSV row or an ERP record needs to know *which*
    # value to fix. `"lines[2].vat_rate"` says that; "cvc-enumeration-valid: Value '24' is not
    # facet-valid with respect to enumeration" — tier 2's phrasing — does not.
    #
    # {#to_s} renders it, so a list of these prints readably wherever a list of strings would.
    Issue = Data.define(:field, :message) do
      def to_s = "#{field}: #{message}"

      # Sorted output is stable output, which keeps error lists diffable in tests and logs.
      #
      # **`Comparable` is deliberately not included**, though `<=>` alone is all sorting needs.
      # Including it puts `Comparable#==` ahead of `Data#==` in the ancestry, and that `==`
      # delegates to this `<=>` — so two issues whose *renderings* coincide compare equal even
      # with different fields, and an `Issue` compares equal to a bare `String`:
      #
      #     Issue[field: "a", message: "b: c"] == Issue[field: "a: b", message: "c"]  # => true
      #     Issue[field: "a", message: "b"]    == "a: b"                              # => true
      #
      # while `eql?` and `hash` kept `Data`'s field-wise semantics, breaking the `==`/`hash`
      # contract and making `Array#include?` disagree with `Hash` membership. Found by a review
      # on 2026-08-24.
      def <=>(other) = to_s <=> other.to_s
    end
  end
end
