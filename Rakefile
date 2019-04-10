# encoding: utf-8

require 'rake/testtask'

require 'simplecov'
require 'coveralls'
SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.command_name 'Unit Tests'
SimpleCov.start

Rake::TestTask.new do |t|
  t.libs = ["lib", "tests"]
  t.test_files = FileList['tests/test_*_spec.rb']
end

task :default => :test
