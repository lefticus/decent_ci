# encoding: utf-8

# this provides some nice output on stdout displaying which unit tests ran
# require 'minitest/reporters'
# Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new # spec-like progress

require 'simplecov'
require 'coveralls'

SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.command_name 'Unit Tests'
SimpleCov.start
