# frozen_string_literal: true

# **Required here rather than relied on.** Nothing else in `lib/` requires `json` — it has
# always arrived via Faraday's own middleware file, which masked the gap: a bare
# `require "ksef_client"` followed by a direct call to this module raised
# `uninitialized constant JSON` until this line existed.
require "json"

module Ksef
  module HTTP
    # The JSON parser {Connection} hands to Faraday's response middleware.
    #
    # ## Why a one-method module exists
    #
    # `json 3.0.0` (2026-09) dropped the second **positional** argument to `JSON.parse`;
    # options must be keywords now. `Faraday::Response::Json#parse` still calls
    # `decoder.public_send(method_name, body, @parser_options || {})` — two positionals — so
    # under json 3 every JSON response from KSeF raised
    # `Faraday::ParsingError: wrong number of arguments (given 2, expected 1)`.
    #
    # That is not a test problem. `ksef_client.gemspec` requires `faraday "~> 2.0"`, faraday
    # declares `json >= 0`, and faraday 2.14.3 is the latest release — so a plain
    # `gem install ksef_client` produced a client that could not read any API response. It
    # reached this project with no commit at all: `Gemfile.lock` is gitignored by library
    # convention, and **rubocop 1.90.0 relaxed its own `json ~> 2.3` pin to `>= 2.3`**, which
    # let json 3.0.0 into CI's fresh resolve. 163 of 1587 examples failed on every Ruby leg.
    #
    # Faraday's response middleware takes a caller-supplied decoder, so the fix swaps the one
    # failing call and keeps every other behaviour the middleware provides — the content-type
    # match with its `;` split, the `to_str` guard, blank body to nil, the
    # `StandardError`/`SyntaxError` rescue, and `Faraday::ParsingError` wrapping. Replacing the
    # middleware wholesale would have meant re-implementing all six, and rewriting the spec
    # that pins the middleware ordering by class.
    #
    # ## Two things here are load-bearing
    #
    # **The second parameter is optional, not merely ignored.** Faraday has *merged* support for
    # json 3 (PR #1687, 2026-08-12) but not released it; that version splats the options as
    # keywords instead. `(body, _options = nil)` satisfies both call shapes — two positionals
    # today, one after the release — so this needs no version check and can simply be deleted
    # once the gem's floor requires a fixed faraday (docs/REFERENCE.md §4.6).
    #
    # **The array form is required.** Passing `decoder: JSON` takes Faraday's
    # `respond_to?(:load)` branch, which calls `JSON.load(body, {})` — and under json 3.0.0
    # that returns **nil** for a perfectly good body, with no exception raised. Measured.
    module JsonDecoder
      # @param body [String]
      # @param _options [Hash, nil] whatever Faraday passes; see above
      # @return [Object] the parsed document
      def self.call(body, _options = nil) = JSON.parse(body)
    end
  end
end
