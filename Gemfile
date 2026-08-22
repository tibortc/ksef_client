# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Development dependencies live here rather than in the gemspec, so that installing the
# gem never drags them in. See DESIGN.md §4.3.
gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.66"
gem "rubocop-rake", "~> 0.6"
gem "rubocop-rspec", "~> 3.0"
gem "simplecov", "~> 0.22", require: false
# LCOV output for Coveralls. SimpleCov's native .resultset.json is not a format the
# uploader understands.
gem "simplecov-lcov", "~> 0.8", require: false
gem "vcr", "~> 6.3"
gem "webmock", "~> 3.23"
gem "yard", "~> 0.9"
