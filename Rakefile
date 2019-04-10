# encoding: utf-8

require 'rubygems'
require 'rake'
require 'rspec/core/rake_task'
require 'coveralls/rake/task'

desc 'Run RSpec'
RSpec::Core::RakeTask.new do |t|
  t.verbose = false
end
task default: :spec
Coveralls::RakeTask.new
