require 'rake/testtask'
task default: "test"

require 'coveralls'
Coveralls.wear!
SimpleCov.command_name 'Unit Tests'

Rake::TestTask.new do |t|
  t.test_files = FileList['tests/**/*_test.rb'] #my directory to tests is 'tests' you can change at you will
end
