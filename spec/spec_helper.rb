require 'coveralls'
require 'logger'
require 'simplecov'
require 'simplecov-console'

# load up the coverage stuff so the shims are in place for loading actual source afterwards
Coveralls.wear!
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
    [
        SimpleCov::Formatter::Console,
        SimpleCov::Formatter::HTMLFormatter
    ]
)
SimpleCov.start do
  add_filter "lib/processor.rb"
end

# load all the source files here to make sure we count everything in coverage calcs
# if Dir.exists?('lib')
#     Dir["lib/**/*.rb"].each {|file| load(file); }
# end
# actually this messes with the coverage calcs, so just not doing it now

# set up a logger global variable for unit testing, but set it to only show fatals
$logger = Logger.new "decent_ci_testing.log", 1
$logger.level = Logger::FATAL
