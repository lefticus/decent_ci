# encoding: utf-8

require 'rake/testtask'

require 'simplecov'
require 'coveralls'
SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.start

Rake::TestTask.new do |t|
  t.libs = ["lib", "spec"]
  t.test_files = FileList['tests/test_*_spec.rb']
end

task :default => :test
