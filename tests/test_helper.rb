# encoding: utf-8

# we use simplecov because that makes coverage results available locally
require 'simplecov'
SimpleCov.start
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                                    SimpleCov::Formatter::HTMLFormatter,
                                                                    SimpleCov::Formatter::CSVFormatter,
                                                                ])
# but for CI we use coveralls.io
require 'coveralls'
Coveralls.wear!('rails')

# this runs all tests
require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new # spec-like progress