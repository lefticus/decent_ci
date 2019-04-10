require 'test/unit'
require_relative '../lib/resultsprocessor'

class TestResultsProcessor < Test::Unit::TestCase
  include ResultsProcessor
  def test_custom_check_parsing_non_json_throws
    parse_custom_check_line({}, "/src/path", "/build/path", "MyErrorMessage")
  end
end
