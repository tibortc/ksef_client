# frozen_string_literal: true

module Ksef
  module UPO
    # The outcome of checking a UPO against the bundled schema (docs/REFERENCE.md §14.3).
    #
    # Two lists rather than one, because a UPO has a category of schema violation that is
    # **upstream's fault and expected**: `upo-v4-3.xsd` fixes the receiving party's name to
    # `"Ministerstwo Finansów"`, while every non-production environment appends a marker. All
    # six of upstream's own worked examples fail upstream's own schema on exactly that
    # element, and nothing else.
    #
    # So those go in {#warnings} and everything else in {#errors}, and {#valid?} ignores the
    # warnings. A validator that reported them as errors would reject every UPO that TEST
    # and DEMO issue — which is the trap this gem would otherwise have walked into, having
    # already built strict XSD validation for FA(3).
    Validation = Data.define(:errors, :warnings, :receiving_party) do
      # True when nothing but the expected environment-marker discrepancy was found.
      def valid? = errors.empty?

      # True when the document also matched the `fixed` value — which in practice means it
      # came from production, or from an environment that has stopped appending a marker.
      def clean? = errors.empty? && warnings.empty?

      # True when the only complaint was the known upstream defect.
      def environment_marked? = errors.empty? && !warnings.empty?

      def messages = errors + warnings

      def to_s
        return "valid" if clean?

        "#{errors.size} error(s), #{warnings.size} warning(s)"
      end
    end
  end
end
