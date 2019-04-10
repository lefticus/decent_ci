# encoding: utf-8

require 'rake/testtask'

Rake::TestTask.new do |task|
  task.libs << %w(test lib)
  task.pattern = 'tests/test_*.rb'
end

task :default => :test
