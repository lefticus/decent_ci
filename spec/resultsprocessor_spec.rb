require 'rspec'
require_relative '../lib/resultsprocessor'
include ResultsProcessor

describe 'ResultsProcessor Testing' do
  context 'when calling parse_custom_check_line' do
    it 'should be ok with no keys at all' do
      message = parse_custom_check_line('/src/path', '/build/path', "{}")
      expect(message.error?).to be_truthy
      expect(message.message).to be_truthy
      expect(message.linenumber).to eql 0
      expect(message.colnumber).to eql 0
    end
    it 'should be add an ID and tool to the message' do
      message = parse_custom_check_line('/src/path', '/build/path', %Q({"tool": "mytool", "id": "this_id"}))
      expect(message.error?).to be_truthy
      expect(message.message).to be_truthy
      expect(message.message).to include "mytool"
      expect(message.message).to include "this_id"
    end
    it 'should return an error' do
      message = parse_custom_check_line('/src/path', '/build/path', 'MyErrorMessage')
      expect(message.error?).to be_truthy
    end
    it 'should return an error for non-json message' do
      message = parse_custom_check_line('/src/path', '/build/path', 'MyErrorMessage')
      expect(message.error?).to be_truthy
    end
    it 'should return an error for json-array message' do
      message = parse_custom_check_line('/src/path', '/build/path', "[{\"key\": 1}]")
      expect(message.error?).to be_truthy
    end
  end
  context 'when calling process_custom_check_results' do
    it 'should handle no data' do
      @build_results = SortedSet.new
      process_custom_check_results('/src/dir', '/build/dir', '', '', 0)
      expect(@build_results.length).to eql 0
    end
    it 'should handle data with an invalid line' do
      @build_results = SortedSet.new
      stdout = "{\"messagetype\": \"warning\"}\n{)\n{\"messagetype\":\"passed\"}"
      process_custom_check_results('/src/dir', '/build/dir', stdout, '', 0)
      expect(@build_results.length).to eql 3  # should be three unique things here
    end
    it 'should handle duplicates' do
      @build_results = SortedSet.new
      stdout = "{}\n{)\n{}"
      process_custom_check_results('/src/dir', '/build/dir', stdout, '', 0)
      expect(@build_results.length).to eql 2  # should only have two here because two are duplicates
    end
    it 'should handle blank lines by ignoring them' do
    end
    it 'should read from stdout and stderr both' do
    end
    it 'should return an array of proper length' do
      # including length 1
    end
    it 'should return failure if exit code was nonzero' do
      @build_results = SortedSet.new
      response = process_custom_check_results('/src/dir', '/build/dir', '', '', 1)
      expect(response).to be_falsey
    end
  end
end
