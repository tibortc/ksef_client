# frozen_string_literal: true

require "nokogiri"
require "digest"
require "fileutils"

# Codegen for the FA(3) metadata under lib/ksef/fa3/generated/ (DESIGN.md §7.1).
#
# Development-only: this file lives outside lib/ so it is never packaged into the gem.
#
# Two properties matter more than elegance here:
#
#   1. **Determinism.** `rake fa3:generate` must produce a byte-identical result on an
#      unchanged schema — that is a definition-of-done gate, and it is what makes
#      regeneration a safe migration path for future schema revisions.
#   2. **Fidelity of ordering.** The schema is built from xsd:sequence, and KSeF rejects
#      documents whose elements are out of order. Sequence order is therefore semantic and
#      is preserved exactly; only collections where order carries no meaning are sorted.
#
# Split into two responsibilities: {Extractor} reads the XSD into plain data, {Renderer}
# turns that data into Ruby source. Keeping them apart means the rendering can be tested
# against hand-built data, with no schema in the picture.
module Fa3Codegen
  # Regenerates, then names the files whose committed content differs — a file the generator
  # emits that the checkout lacks included, which is why the comparison is globbed *after*
  # generating. Comparing over the pre-run glob silently stops checking exactly those.
  def self.drifted_files
    before = Dir["#{OUT_DIR}/*.rb"].to_h { |file| [file, File.read(file, encoding: "UTF-8")] }
    Generator.new.generate!
    after = Dir["#{OUT_DIR}/*.rb"].to_h { |file| [file, File.read(file, encoding: "UTF-8")] }
    [after.reject { |path, body| before[path] == body }.keys, after.size]
  end

  XS = { "xsd" => "http://www.w3.org/2001/XMLSchema" }.freeze
  SCHEMA_DIR = "lib/ksef/fa3/schema"
  MAIN_SCHEMA = "#{SCHEMA_DIR}/schemat_FA(3)_v1-0E.xsd".freeze
  OUT_DIR = "lib/ksef/fa3/generated"
  ROOT_ELEMENT = "Faktura"

  # Reads the pinned XSDs into plain Ruby data.
  class Extractor
    # Where a complexType may declare an attribute. Never a descendant axis — see
    # {#attributes_of} for what that cost. Above `private` because a constant is not
    # scoped by it either way.
    ATTRIBUTE_PATHS = [
      "./xsd:attribute[@name]",
      "./xsd:simpleContent/xsd:extension/xsd:attribute[@name]",
      "./xsd:complexContent/xsd:extension/xsd:attribute[@name]"
    ].freeze

    def initialize(schema_dir: SCHEMA_DIR, main: MAIN_SCHEMA)
      @schema_dir = schema_dir
      @main = main
      @doc = parse(main)
    end

    attr_reader :main

    # @return [String] e.g. "1-0E", from the fixed wersjaSchemy attribute
    def schema_version
      @doc.at_xpath('//xsd:attribute[@name="wersjaSchemy"]', XS)&.[]("fixed") ||
        raise("wersjaSchemy not found in #{@main} — schema shape changed, review the generator")
    end

    # Every named simpleType carrying enumerations, across the main schema and its base
    # schemas. Keyed by XSD type name (sorted); values keep document order, which is the
    # schema's own ordering and is meaningful for things like VAT rates.
    #
    # `Dir[]` is sorted as of Ruby 3.0, and the floor is 3.2, so the traversal is stable.
    def enums
      Dir["#{@schema_dir}/**/*.xsd"].each_with_object({}) do |file, acc|
        parse(file).xpath("//xsd:simpleType[@name]", XS).each do |simple_type|
          values = simple_type.xpath(".//xsd:enumeration", XS).map { |e| e["value"] }
          acc[simple_type["name"]] ||= values unless values.empty?
        end
      end.sort.to_h
    end

    # Content models keyed by a stable identifier:
    #   - named complexTypes by their XSD name, e.g. "TNaglowek"
    #   - anonymous ones by their element path, e.g. "Faktura/Podmiot1/DaneKontaktowe"
    #
    # Paths rather than leaf names because leaf names collide — DaneKontaktowe appears
    # under all four subject elements — and a path stays stable if upstream adds another.
    #
    # An anonymous type nested inside a *named* one is rooted at the type name rather than
    # at `Faktura`, so `KodFormularza` is keyed "TNaglowek/KodFormularza". A named type may
    # be referenced from more than one place, so its own name is the stable root; an element
    # path through one of its references would not be.
    #
    # **Descending into named types was missing entirely until 2026-08-26**, which is how
    # `KodFormularza` — the one element in FA(3) that carries fixed attributes, and the only
    # one this serializer writes attributes for — came to have no entry at all. What made
    # that survive is {#attributes_of}'s own bug: the descendant axis leaked the attributes
    # up to `TNaglowek`, so the caller found them one level too high and emitted a correct
    # document from an incorrect lookup. Two defects, each hiding the other.
    def types
      acc = {}

      @doc.xpath("/xsd:schema/xsd:complexType[@name]", XS).each do |ct|
        acc[ct["name"]] = describe(ct)
        collect_nested(ct, [ct["name"]], acc)
      end

      root = @doc.at_xpath("/xsd:schema/xsd:element[@name=\"#{ROOT_ELEMENT}\"]", XS) ||
             raise("root element #{ROOT_ELEMENT} not found in #{@main}")
      collect_anonymous(root.at_xpath("./xsd:complexType", XS), [ROOT_ELEMENT], acc)

      acc.sort.to_h
    end

    private

    def parse(path)
      Nokogiri::XML(File.read(path, encoding: "UTF-8"))
    end

    def collect_anonymous(complex_type, path, acc)
      return unless complex_type

      acc[path.join("/")] = describe(complex_type)
      collect_nested(complex_type, path, acc)
    end

    # The anonymous complexTypes declared on this type's own elements. Split out of
    # {#collect_anonymous} so a named type can be descended into without first being
    # described under a path-shaped key it does not have.
    def collect_nested(complex_type, path, acc)
      immediate_elements(complex_type).each do |el|
        nested = el.at_xpath("./xsd:complexType", XS)
        collect_anonymous(nested, path + [el["name"]], acc) if nested
      end
    end

    def describe(complex_type)
      { content: content_model(complex_type), attributes: attributes_of(complex_type) }
    end

    # The content model as a single root particle, never an unwrapped list.
    #
    # This matters: four complexTypes (Zwolnienie, NoweSrodkiTransportu, PMarzy,
    # FakturaZaliczkowa) have a top-level <choice>. Returning their children as a bare
    # list would silently convert "exactly one of these" into "all of these, in order" —
    # the validator would accept mutually exclusive branches together, and the serializer
    # would have no idea they were alternatives.
    #
    # nil for simpleContent types, which have attributes and text but no element children.
    def content_model(complex_type)
      compositor = compositor_of(complex_type)
      return unless compositor

      compositor_particle(compositor)
    end

    def compositor_of(node)
      node.element_children.find { |c| %w[sequence choice].include?(c.name) }
    end

    def compositor_particle(node)
      {
        kind: node.name.to_sym,
        min: occurs(node, "minOccurs"),
        max: occurs(node, "maxOccurs"),
        particles: particles(node)
      }
    end

    def particles(compositor)
      compositor.element_children.filter_map do |child|
        case child.name
        when "element" then element_particle(child)
        when "sequence", "choice" then compositor_particle(child)
        end
      end
    end

    def element_particle(element)
      particle = {
        kind: :element,
        name: element["name"],
        min: occurs(element, "minOccurs"),
        max: occurs(element, "maxOccurs")
      }
      particle[:type] = element["type"] if element["type"]

      inline_base = element.at_xpath("./xsd:simpleType/xsd:restriction", XS)&.[]("base")
      particle[:base] = inline_base if inline_base

      particle
    end

    # Elements directly inside this complexType, through compositor nesting but never
    # through a nested complexType.
    def immediate_elements(complex_type)
      compositor = compositor_of(complex_type)
      compositor ? flatten_elements(compositor) : []
    end

    def flatten_elements(compositor)
      compositor.element_children.flat_map do |child|
        case child.name
        when "element" then [child]
        when "sequence", "choice" then flatten_elements(child)
        else []
        end
      end
    end

    # Attributes this type **declares**, which is not the same as attributes reachable
    # beneath it.
    #
    # The axis here used to be `.//`, and that is a bug of the same family as everything
    # else in this file: it descends through nested anonymous complexTypes, so a type
    # inherited every attribute of every element under it. Seven types were affected —
    # `TNaglowek` and `KodFormularza` each claimed `kodSystemowy`/`wersjaSchemy`, and
    # `Faktura`, `Zalacznik`, `BlokDanych`, `Tabela` and the attachment's own `TNaglowek`
    # each claimed `Kol`'s `Typ`. Generated metadata that reads plausibly and is wrong is
    # worse than metadata that is missing, because nothing downstream can tell.
    #
    # An attribute is declared either directly or on an extension, so both are read and
    # neither is a descent: `xsd:simpleContent`/`xsd:complexContent` are a wrapper around
    # *this* type's own definition, not a child type.
    def attributes_of(complex_type)
      attrs = complex_type.xpath(ATTRIBUTE_PATHS.join("|"), XS).map do |attr|
        {
          name: attr["name"], type: attr["type"], use: attr["use"] || "optional",
          fixed: attr["fixed"], values: inline_values(attr)
        }.compact
      end
      # Names are unique within a type, so this sort has no ties to order and is total.
      attrs.sort_by { |a| a[:name] }
    end

    # The permitted values of an attribute restricted by an *inline* simpleType.
    #
    # {#enums} keys on `xsd:simpleType[@name]`, so an anonymous restriction hanging off an
    # attribute is invisible to it. FA(3) has exactly one — `Kol/@Typ`'s six column types —
    # and without this the only way to enforce it is to type the six values into a Ruby
    # constant, which DESIGN.md §7.1 forbids: hand-written models consume schema metadata
    # and must never restate it.
    #
    # nil rather than [] when there is no restriction, so {#attributes_of}'s `compact` keeps
    # the key out of the rendered Hash entirely — an empty Array would read as "enumerated,
    # with nothing permitted".
    def inline_values(attr)
      values = attr.xpath("./xsd:simpleType/xsd:restriction/xsd:enumeration", XS).map { |e| e["value"] }
      values.empty? ? nil : values
    end

    # `unbounded` becomes nil, meaning "no upper limit" — easier to reason about than a
    # sentinel string in every downstream comparison.
    def occurs(node, attribute)
      raw = node[attribute]
      return 1 if raw.nil?
      return nil if raw == "unbounded"

      Integer(raw, 10)
    end
  end

  # Turns extracted data into deterministic Ruby source.
  class Renderer
    # Fixed explicitly rather than relying on insertion order, so output cannot drift
    # with refactoring.
    #
    # **Every key any rendered Hash can hold must appear here.** {#sorted_keys} maps an
    # unlisted key to one shared rank, and `sort_by` is not stable — so two unlisted keys
    # tie and their order is whatever the sort happens to do, which is exactly how a
    # determinism bug reached CI from `tasks/field_mapping.rb`. `use` and `fixed` were
    # unlisted and had been tying since attributes were first rendered; `values` would have
    # made three.
    KEY_ORDER = %i[kind name type base use fixed values min max particles content attributes].freeze

    def initialize(extractor)
      @extractor = extractor
    end

    def enums_source
      entries = @extractor.enums.map do |name, values|
        rendered = values.map { |v| "      #{v.inspect}" }.join(",\n")
        indent("#{name.inspect} => [\n#{rendered}\n    ].freeze", 10)
      end

      <<~RUBY
        #{header("Enumerations from every named xsd:simpleType that restricts by value.")}
        module Ksef
          module FA3
            module Generated
              # Permitted values per XSD simple type, keyed by the XSD type name. Values
              # keep schema order, which is meaningful — VAT rates are listed by rate.
              module Enums
                ALL = {
        #{entries.join(",\n")}
                }.freeze

                # @return [Array<String>, nil]
                def self.values_for(type_name) = ALL[type_name]

                # @return [Boolean] whether the value is permitted for that type
                def self.valid?(type_name, value) = ALL.fetch(type_name, []).include?(value)
              end
            end
          end
        end
      RUBY
    end

    def types_source
      entries = @extractor.types.map { |key, meta| indent("#{key.inspect} => #{render(meta)},", 10) }

      <<~RUBY
        #{header("Content models for every complexType reachable from the #{ROOT_ELEMENT} root.")}
        module Ksef
          module FA3
            module Generated
              # Element ordering, occurrence rules and attributes per complexType.
              #
              # Keys are XSD type names for named types, and element paths for anonymous
              # ones (e.g. "Faktura/Podmiot1/DaneKontaktowe"), because leaf names collide.
              #
              # `content` is a single root particle, not a flat list: :sequence preserves
              # the order KSeF requires, and :choice records that exactly one branch
              # applies. Four types have a *top-level* choice, so unwrapping the root
              # would lose that distinction. nil for simpleContent types.
              # `max` of nil means unbounded.
              module Types
                ALL = {
        #{entries.join("\n")}
                }.freeze

                # @return [Hash, nil]
                def self.[](key) = ALL[key]

                # Element particles in schema order, flattened through compositors.
                #
                # Note this deliberately discards choice semantics — use it for ordering
                # only. Anything enforcing "exactly one of" must walk `content` itself.
                #
                # @return [Array<Hash>]
                def self.ordered_elements(key)
                  root = ALL.fetch(key, {})[:content]
                  root ? flatten([root]) : []
                end

                # Whether this type's root compositor is a choice, i.e. its top-level
                # particles are mutually exclusive alternatives.
                def self.root_choice?(key)
                  ALL.fetch(key, {}).dig(:content, :kind) == :choice
                end

                def self.flatten(particles)
                  particles.flat_map do |p|
                    p[:kind] == :element ? [p] : flatten(p[:particles] || [])
                  end
                end
                private_class_method :flatten
              end
            end
          end
        end
      RUBY
    end

    private

    def header(description)
      <<~HEADER
        # frozen_string_literal: true

        # GENERATED by `rake fa3:generate` from FA(3) #{@extractor.schema_version} — DO NOT EDIT.
        #
        # #{description}
        #
        # Source: #{@extractor.main}
        # SHA256: #{Digest::SHA256.file(@extractor.main).hexdigest}
        #
        # Regenerate rather than editing. Hand-written models consume this metadata for
        # element ordering, occurrence rules and enum membership; they must never restate
        # it (DESIGN.md §7.1).
      HEADER
    end

    def render(value, depth = 0)
      case value
      when Hash then render_hash(value, depth)
      when Array then render_array(value, depth)
      else value.inspect
      end
    end

    def render_hash(hash, depth)
      return "{}" if hash.empty?

      pad = "  " * (depth + 1)
      pairs = sorted_keys(hash).map { |key| "#{pad}#{key.inspect} => #{render(hash[key], depth + 1)}" }
      "{\n#{pairs.join(",\n")}\n#{"  " * depth}}"
    end

    def render_array(array, depth)
      return "[]" if array.empty?

      pad = "  " * (depth + 1)
      items = array.map { |v| pad + render(v, depth + 1) }
      "[\n#{items.join(",\n")}\n#{"  " * depth}]"
    end

    def sorted_keys(hash)
      hash.keys.sort_by { |k| KEY_ORDER.index(k) || KEY_ORDER.size }
    end

    def indent(text, spaces)
      text.lines.map { |l| l.strip.empty? ? l : (" " * spaces) + l }.join
    end
  end

  # Writes the rendered sources to disk.
  class Generator
    def initialize(out_dir: OUT_DIR, extractor: Extractor.new)
      @out_dir = out_dir
      @renderer = Renderer.new(extractor)
    end

    def generate!
      FileUtils.mkdir_p(@out_dir)
      write("#{@out_dir}/enums.rb", @renderer.enums_source)
      write("#{@out_dir}/types.rb", @renderer.types_source)
    end

    private

    def write(path, body)
      File.write(path, body)
      puts "  wrote #{path} (#{body.lines.size} lines)"
    end
  end
end
