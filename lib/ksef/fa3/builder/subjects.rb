# frozen_string_literal: true

module Ksef
  module FA3
    class Builder
      # Turning the DSL's keyword arguments into model objects: shorthand translation, the
      # unknown-option check, and the three shapes an address may be given in.
      #
      # Extracted alongside {Advances} and {Corrections} when the attachment call pushed the
      # class past its length limit. The split is not arbitrary — everything here is about
      # *arguments*, and nothing about it is part of the DSL surface a caller reads.
      module Subjects
        private

        def subject(attributes, role:)
          normalised = normalise(attributes, SUBJECT_KEYS, {}, "#{role} subject")
          require_keys(normalised, %i[nip name address], role)
          # `normalise` returns a fresh Hash, so replacing the address in place is safe —
          # and reads better than relying on splat-then-override precedence.
          normalised[:address] = coerce_address(normalised[:address], role)
          Subject.new(**normalised)
        end

        # Accepts an {Address}, a Hash of its attributes, or a pre-formatted string — the
        # last because FA(3) models an address as free-text lines anyway (see {Address}).
        def coerce_address(value, role)
          case value
          when Address then value
          when String then Address.new(line1: value)
          when Hash
            Address.new(**normalise(value.transform_keys(&:to_sym), ADDRESS_KEYS, {}, "#{role} address"))
          else
            raise ValidationError,
                  "#{role} address must be a Ksef::FA3::Address, a Hash of its fields, or a formatted " \
                  "String; got #{value.class}"
          end
        end

        # Translates shorthand, then rejects anything the target object does not accept.
        def normalise(attributes, permitted, aliases, what)
          aliases.each do |short, long|
            next unless attributes.key?(short) && attributes.key?(long)

            raise ValidationError, "Pass either #{short}: or #{long}: to #{what}, not both"
          end

          translated = attributes.to_h { |key, value| [aliases.fetch(key, key), value] }
          unknown = translated.keys - permitted
          raise ValidationError, unknown_message(unknown, permitted, aliases, what) unless unknown.empty?

          translated
        end

        def unknown_message(unknown, permitted, aliases, what)
          message = "Unknown #{what} option(s) #{unknown.map(&:inspect).join(", ")}. " \
                    "Permitted: #{permitted.join(", ")}"
          return message if aliases.empty?

          "#{message}. Shorthand: #{aliases.map { |short, long| "#{short} for #{long}" }.join(", ")}"
        end

        def require_keys(attributes, keys, what)
          missing = keys.reject { |key| attributes.key?(key) }
          return if missing.empty?

          raise ValidationError, "Incomplete #{what}, missing #{missing.join(", ")}"
        end
      end
    end
  end
end
