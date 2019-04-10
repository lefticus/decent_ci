require 'rspec'
require_relative '../lib/codemessage'

describe 'CodeMessage Testing' do
  before do
    # Do nothing
  end

  after do
    # Do nothing
  end

  context 'when constructing code messages' do
    it 'should properly check warning type' do
      c = CodeMessage.new("filename", 1, 1, "warning", "message")
      expect(c.is_warning).to be_truthy
      c = CodeMessage.new("filename", 1, 1, "WaRning", "message")
      expect(c.is_warning).to be_truthy
      c = CodeMessage.new("filename", 1, 1, "warMing", "message")
      expect(c.is_warning).to be_nil
    end
    it 'should properly check error type' do
      c = CodeMessage.new("filename", 1, 1, "error", "message")
      expect(c.is_error).to be_truthy
      c = CodeMessage.new("filename", 1, 1, "ERror", "message")
      expect(c.is_error).to be_truthy
      c = CodeMessage.new("filename", 1, 1, "Airer", "message")
      expect(c.is_error).to be_nil
    end
    it 'should properly compare code messages' do
      c_base = CodeMessage.new("filename", 1, 1, "warning", "message")
      c_file = CodeMessage.new("filename2", 1, 1, "warning", "message")
      c_line = CodeMessage.new("filename", 2, 1, "warning", "message")
      c_colu = CodeMessage.new("filename", 1, 2, "warning", "message")
      c_type = CodeMessage.new("filename", 1, 1, "error", "message")
      c_mess = CodeMessage.new("filename", 1, 1, "warning", "message2")
      c_equal = CodeMessage.new("filename", 1, 1, "warning", "message")
      expect(c_base <=> c_file).not_to be_equal(0)
      expect(c_base <=> c_line).not_to be_equal(0)
      expect(c_base <=> c_colu).not_to be_equal(0)
      expect(c_base <=> c_type).not_to be_equal(0)
      expect(c_base <=> c_mess).not_to be_equal(0)
      expect(c_base <=> c_equal).to be_equal(0)
    end
  end
end
