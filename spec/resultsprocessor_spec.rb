require 'rspec'
require_relative '../lib/resultsprocessor'
include ResultsProcessor

describe 'ResultsProcessor Testing' do
  context 'when calling parse_custom_check_line' do
    it 'should be ok with no keys at all' do
      message = parse_custom_check_line({}, "/src/path", "/build/path", "{}")
      expect(message.is_error).to be_truthy
    end
    it 'should return an error' do
      message = parse_custom_check_line({}, "/src/path", "/build/path", "MyErrorMessage")
      expect(message.is_error).to be_truthy
    end
    it 'should return an error for non-json message' do
      message = parse_custom_check_line({}, "/src/path", "/build/path", "MyErrorMessage")
      expect(message.is_error).to be_truthy
    end
    it 'should return an error for json-array message' do
      message = parse_custom_check_line({}, "/src/path", "/build/path", "[{\"key\": 1}]")
      expect(message.is_error).to be_truthy
    end
  end
end
