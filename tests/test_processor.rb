require 'test/unit'
require_relative '../lib/processor'

class TestProcessor < Test::Unit::TestCase
  def test_gets_value
    processor_count.to_i  # should not throw
  end
end
