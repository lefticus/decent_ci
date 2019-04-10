require 'minitest'
require_relative '../lib/processor'

class TestProcessor < Minitest::Test
  def test_gets_value
    processor_count.to_i  # should not throw
  end
end
