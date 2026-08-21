# frozen_string_literal: true

require "zeitwerk"

# Ruby client for KSeF 2.0, the Polish National e-Invoice System.
#
# Two decoupled subsystems live under this namespace (DESIGN.md §5):
#   - {Ksef::Client} and friends — transport: auth, crypto, sessions, invoices.
#   - {Ksef::FA3}                — the FA(3) invoice builder, usable with no HTTP at all.
module Ksef
  class << self
    # The gem's Zeitwerk loader. Exposed for `loader.eager_load` in forking servers.
    attr_reader :loader
  end

  @loader = Zeitwerk::Loader.new.tap do |loader|
    loader.push_dir(__dir__)
    # `ksef_client.rb` is the gem entry point, not a constant definition (DESIGN.md §5.3).
    loader.ignore("#{__dir__}/ksef_client.rb")
    # `errors.rb` defines the whole hierarchy and no `Ksef::Errors`, so it cannot follow
    # Zeitwerk's file-to-constant rule. It is tiny and always needed — load it eagerly.
    loader.ignore("#{__dir__}/ksef/errors.rb")
    loader.inflector.inflect(
      "fa3" => "FA3",
      "http" => "HTTP",
      "version" => "VERSION"
    )
    loader.setup
  end
end

require_relative "ksef/errors"
