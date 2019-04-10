require 'minitest/autorun'
require 'processor' # don't worry, this works

class TestProcessor < Minitest::Test
  def test_gets_value
    num_processors = processor_count()
    num_processors.to_i  # should not throw
  end
end
