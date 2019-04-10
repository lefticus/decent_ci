require 'minitest/autorun'
require_relative '../lib/resultsprocessor'

class TestResultsProcessor < Minitest::Test
  include ResultsProcessor
  def test_custom_check_parsing_non_json_throws
    parse_custom_check_line({}, "/src/path", "/build/path", "MyErrorMessage")
  end
end

