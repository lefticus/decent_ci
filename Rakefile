require 'rake/testtask'
task default: "test"

require 'coveralls'
Coveralls.wear!

Rake::TestTask.new do |task|
  task.pattern = 'tests/*_test.rb'
end
