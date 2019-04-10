require 'rspec'
require_relative '../lib/resultsprocessor'
include ResultsProcessor

describe 'ResultsProcessor Testing' do
  before do
    # Do nothing
  end

  after do
    # Do nothing
  end

  context 'when getting non json message' do
    it 'should return an error' do
      message = parse_custom_check_line({}, "/src/path", "/build/path", "MyErrorMessage")
      expect(message.is_error).to be_truthy
    end
  end
end