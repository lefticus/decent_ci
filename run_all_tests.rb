require_relative 'tests/test_helper'

Dir[File.dirname(File.absolute_path(__FILE__)) + 'tests/**/test_*.rb'].each {|file| require file }
