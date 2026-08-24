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
      def <=>(other) = to_s <=> other.to_s
      include Comparable
    end
  end
end
