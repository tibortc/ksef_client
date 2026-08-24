# frozen_string_literal: true

module Ksef
  module FA3
    class Builder
      # The DSL calls that make an invoice a correction, and the assembly behind them.
      #
      # Split out of {Builder} for length, and along the same seam the validator splits: a
      # correction is a self-contained subject with its own value objects (docs/REFERENCE.md
      # §8.4). Mixed into {Builder}, so `@correction` and `@corrected` are its state.
      module Corrections
        # Makes this a correction. Optional next to {#corrects}, which is what a correction
        # actually needs; call this for the reason, the effect date and the rest.
        #
        # @param attributes [Hash] `:reason`, `:effect`, `:period`, `:corrected_number`,
        #   `:previous_seller`, `:previous_buyers` — see {Correction}
        def correction(**attributes)
          @correction = normalise(attributes, CORRECTION_KEYS, {}, "correction")
        end

        # Names one invoice this correction corrects. Call once per corrected invoice; a
        # collective correction under art. 106j ust. 3 names many.
        #
        # @param attributes [Hash] `:number`, `:issue_date`, and `:ksef_number` unless the
        #   corrected invoice was issued outside KSeF
        def corrects(**attributes)
          @corrected << CorrectedInvoice.new(**normalise(attributes, CORRECTED_KEYS, {}, "corrects"))
        end

        private

        # Assembled at the end rather than as {#correction} is called, because a correction is
        # only well-formed once it names a corrected invoice — and the DSL takes those one at a
        # time. Present whenever either half was used, so `corrects` alone is enough and
        # `correction` alone fails with {Correction::NAMES_NOTHING} rather than silently
        # producing an invoice that is not a correction.
        def assembled_correction
          return nil if @correction.nil? && @corrected.empty?

          Correction.new(**(@correction || {}), corrected: @corrected)
        end
      end
    end
  end
end
