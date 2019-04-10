require 'coveralls'
require 'simplecov'
require 'simplecov-console'
Coveralls.wear!
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
    [
        SimpleCov::Formatter::Console,
        SimpleCov::Formatter::HTMLFormatter
    ]
)
SimpleCov.start
