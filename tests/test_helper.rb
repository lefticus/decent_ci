# encoding: utf-8

# we use simplecov because that makes coverage results available locally
require 'simplecov'
SimpleCov.start

# but for CI we use coveralls.io
require 'coveralls'
Coveralls.wear!('rails')

# this runs all tests
require 'minitest/autorun'
