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
      stdout = "{}\n{)\n{}"  # note second is invalid
      process_custom_check_results('/src/dir', '/build/dir', stdout, '', 0)
      expect(@build_results.length).to eql 2  # should only have two here because two are duplicates
    end
    it 'should handle blank lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "{}\n\n{)"
      process_custom_check_results('/src/dir', '/build/dir', stdout, '', 0)
      expect(@build_results.length).to eql 2  # should have two here
    end
    it 'should read from stdout and stderr both' do
      @build_results = SortedSet.new
      stdout = "{}\n\n{)"
      stderr = "{\"messagetype\": \"warning\"}\n{\"messagetype\":\"passed\"}"
      process_custom_check_results('/src/dir', '/build/dir', stdout, stderr, 0)
      expect(@build_results.length).to eql 4  # should have two here
    end
    it 'should return failure if exit code was nonzero' do
      @build_results = SortedSet.new
      response = process_custom_check_results('/src/dir', '/build/dir', '', '', 1)
      expect(response).to be_falsey
    end
  end

  context 'when calling recover_file_case' do
    it 'should just return the original file case on Linux' do
      expect(recover_file_case('boy one')).to eql 'boy one'
      expect(recover_file_case('mY nAmE iS mUd')).to eql 'mY nAmE iS mUd'
      expect(recover_file_case('BOY TWO')).to eql 'BOY TWO'
    end
  end

  context 'when calling parse_cppcheck_line' do
    it 'should properly parse a few variations' do
      message = '[File.cc]:23:Error:Hey'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = '[File.cc]:23:PASS:Hey'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_falsey
      message = '[]:23:PASS:Hey'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response).to be_nil
    end
  end

  context 'when calling process_cppcheck_results' do
    it 'should handle no data' do
      @build_results = SortedSet.new
      process_cppcheck_results('/src/dir', '/build/dir', '', 0)
      expect(@build_results.length).to eql 0
    end
    it 'should handle invalid lines by ignoring them' do
      @build_results = SortedSet.new
      stderr = "[File.cc]:23:Error:Hey\nOH HIA"
      process_cppcheck_results('/src/dir', '/build/dir', stderr, 0)
      expect(@build_results.length).to eql 1
    end
    it 'should handle blank lines by ignoring them' do
      @build_results = SortedSet.new
      stderr = "[File.cc]:23:Error:Hey\n\n[File2.cc]:23:Error:Hey"
      process_cppcheck_results('/src/dir', '/build/dir', stderr, 0)
      expect(@build_results.length).to eql 2
    end
  end

  context 'when calling process_cmake_results' do

  end

  context 'when calling parse_generic_line' do
    it 'should properly parse a few variations' do
      message = 'Something:32: Hey there'
      response = parse_generic_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = 'Something.cc:9: Hey there'
      response = parse_generic_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = ':32: Hey there'
      response = parse_generic_line('/src/path/', '/build/path', message)
      expect(response).to be_nil
    end
  end

  context 'when calling parse_msvc_line' do
    it 'should properly parse a few variations' do
      message = 'Something.cc(32): Error 332: ad [message text]'
      response = parse_msvc_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = 'Something.cc : Error 332: ad [message text]'  # second form without line number
      response = parse_msvc_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = '(32): Error: ad [message text]'  # missing name and error code, should return nil
      response = parse_msvc_line('/src/path/', '/build/path', message)
      expect(response).to be_nil
    end
  end

  context 'when calling process_msvc_results' do
    it 'should handle no data' do
      @build_results = SortedSet.new
      process_msvc_results('/src/dir', '/build/dir', '', 0)
      expect(@build_results.length).to eql 0
    end
    it 'should handle invalid lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "Something.cc(32): Error 332: ad [message text]\nOH HIA"
      process_msvc_results('/src/dir', '/build/dir', stdout, 0)
      expect(@build_results.length).to eql 1
    end
    it 'should handle blank lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "Something.cc(32): Error 332: ad [message text]\n\nSomething.cc(33): Error 332: ad [message text]"
      process_msvc_results('/src/dir', '/build/dir', stdout, 0)
      expect(@build_results.length).to eql 2
    end
  end

  context 'when calling parse_gcc_line' do
    it 'should properly parse a few variations' do
      message = 'Something.cc:32:4: Error: Some message stuff'
      response = parse_gcc_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = 'Something.cc:32:4: multiple definition of variable'  # second form without error type (linker?)
      response = parse_gcc_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = ':32:4: Message-Without-Error'  # missing file name, should return nil
      response = parse_gcc_line('/src/path/', '/build/path', message)
      expect(response).to be_nil
    end
  end

  context 'when calling process_gcc_results' do
    it 'should handle no data' do
      @build_results = SortedSet.new
      process_gcc_results('/src/dir', '/build/dir', '', 0)
      expect(@build_results.length).to eql 0
    end
    it 'should handle invalid lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "Something.cc:32:4: Error: Some message stuff\nOH HIA"
      process_gcc_results('/src/dir', '/build/dir', stdout, 0)
      expect(@build_results.length).to eql 1
    end
    it 'should handle blank lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "Something.cc:32:4: Error: Some message stuff\n\nSomething.cc:33:4: Error: Some message stuff"
      process_gcc_results('/src/dir', '/build/dir', stdout, 0)
      expect(@build_results.length).to eql 2
    end
    it 'should catch multiline linker messages' do
      @build_results = SortedSet.new
      stdout = "Undefined symbols for architecture.\n ExtraStuff\nBacktonormalmessages"
      process_gcc_results('/src/dir', '/build/dir', stdout, 0)
      expect(@build_results.length).to eql 1
    end
  end

  context 'when calling parse_error_messages' do
    it 'should catch gcc, msvc, and generic messages' do
      msvc_message = 'Something.cc(32): Error 332: ad [message text]'
      gcc_message = 'Something.cc:32:4: Error: Some message stuff'
      generic_message = 'Something:32: Hey there'
      full_output = "#{msvc_message}\n#{gcc_message}\nINVALID\n#{generic_message}\n\n"
      build_res = parse_error_messages('/src/dir', '/build/dir', full_output)
      expect(build_res.length).to eql 3
    end
  end

  context 'when calling parse_python_or_latex_line' do

  end

  context 'when calling process_python_results' do

  end

  context 'when calling parse_package_names' do

  end

  context 'when calling process_lcov_results' do

  end

  context 'when calling process_ctest_results' do

  end
end
