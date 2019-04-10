# encoding: utf-8

require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new # spec-like progress
