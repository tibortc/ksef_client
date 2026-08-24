# frozen_string_literal: true

require "zeitwerk"

# Required centrally rather than per-file. Each is a declared runtime dependency used across
# the gem, and relying on whichever autoloaded file happens to require it first makes the
# constant's availability depend on call order.
#
# Nokogiri joined this list on 2026-08-24 for exactly the reason the comment predicts. Every
# file that uses it required it, but Zeitwerk defers loading those files, so after
# `require "ksef_client"` the constant did not exist until something touched the serializer or
# the parser. That made `spec/ksef/fa3/round_trip_spec.rb` pass or fail depending on the RSpec
# seed, and it would have bitten any user whose first call was not a serialising one.
require "bigdecimal"
require "date"
require "nokogiri"

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
      "nip" => "NIP",
      # Urzędowe Poświadczenie Odbioru — an acronym, so `Ksef::UPO`, not `Ksef::Upo`.
      # Declared with the pinned schema rather than with the first class under it, so the
      # namespace is never briefly wrong.
      "upo" => "UPO",
      "version" => "VERSION"
    )
    loader.setup
  end
end

require_relative "ksef/errors"
