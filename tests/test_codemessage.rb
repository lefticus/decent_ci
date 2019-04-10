require 'test/unit'
require_relative '../lib/codemessage'

class TestCodeMessage < Test::Unit::TestCase
  def test_warning_construction
    c = CodeMessage.new("filename", 1, 1, "warning", "message")
    assert c.is_warning
    c = CodeMessage.new("filename", 1, 1, "WaRning", "message")
    assert c.is_warning
    c = CodeMessage.new("filename", 1, 1, "warMing", "message")
    assert_nil c.is_warning
  end
  def test_error_construction
    c = CodeMessage.new("filename", 1, 1, "error", "message")
    assert c.is_error
    c = CodeMessage.new("filename", 1, 1, "ERror", "message")
    assert c.is_error
    c = CodeMessage.new("filename", 1, 1, "Airer", "message")
    assert_nil c.is_error
  end
  def test_code_message_comparison
    c_base = CodeMessage.new("filename", 1, 1, "warning", "message")
    c_file = CodeMessage.new("filename2", 1, 1, "warning", "message")
    c_line = CodeMessage.new("filename", 2, 1, "warning", "message")
    c_colu = CodeMessage.new("filename", 1, 2, "warning", "message")
    c_type = CodeMessage.new("filename", 1, 1, "error", "message")
    c_mess = CodeMessage.new("filename", 1, 1, "warning", "message2")
    c_equal = CodeMessage.new("filename", 1, 1, "warning", "message")
    assert((c_base <=> c_file) <=> 0)
    assert((c_base <=> c_line) <=> 0)
    assert((c_base <=> c_colu) <=> 0)
    assert((c_base <=> c_type) <=> 0)
    assert((c_base <=> c_mess) <=> 0)
    assert((c_base <=> c_equal) == 0)
  end
end
