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
    # once we test on Windows, we should ONLY test recover_file_case on there, and eliminate the IF WINDOWS block
  end

  context 'when calling parse_cppcheck_line' do
    it 'should properly parse a few variations' do
      message = '[File.cc:23]: (error) Hey'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = '[File.cc:23]: (PASS) Hey'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_falsey
      message = '[:23]: (PASS) Hey'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response).to be_nil
      message = '[src/EnergyPlus/PipeHeatTransfer.cc:1895]: (error) Uninitialized variable: AirVel'
      response = parse_cppcheck_line('/src/path/', '/build/path', message)
      expect(response).to be_truthy
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
      stderr = "[File.cc:23]: (Error) Hey\nOH HIA"
      process_cppcheck_results('/src/dir', '/build/dir', stderr, 0)
      expect(@build_results.length).to eql 1
    end
    it 'should handle blank lines by ignoring them' do
      @build_results = SortedSet.new
      stderr = "[File.cc:23]: (Error) Hey\n\n[File2.cc:23]: (Error) Hey"
      process_cppcheck_results('/src/dir', '/build/dir', stderr, 0)
      expect(@build_results.length).to eql 2
    end
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
      message = 'C:\\Blah\\File.hh(21): error C2727: \'some_key\': \'some_value\' and things (compiling a.cc)'
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
    #  expect(response.error?).to be_truthy
      message = 'Something.cc:32: multiple definition of variable'  # second form without error type (linker?)
      response = parse_gcc_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
      message = ':32:4: Message-Without-Error'  # missing file name, should return nil
      response = parse_gcc_line('/src/path/', '/build/path', message)
    #  expect(response).to be_nil
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
    it 'should properly parse python error messages' do
      message = "# TypeError: cannot concatenate \'str\' and \'int\' objects"
      response = parse_python_or_latex_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
    end
    it 'should properly parse latex error messages' do
      message = '! LaTeX Error: Environment itemize undefined.'
      response = parse_python_or_latex_line('/src/path/', '/build/path', message)
      expect(response.error?).to be_truthy
    end
  end

  context 'when calling process_python_results' do
    it 'should handle no data' do
      @build_results = SortedSet.new
      process_python_results('/src/dir', '/build/dir', '','', 0)
      expect(@build_results.length).to eql 0
    end
    it 'should handle invalid lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "# TypeError: cannot concatenate \'str\' and \'int\' objects\nOH HAI"
      process_python_results('/src/dir', '/build/dir', stdout, '',0)
      expect(@build_results.length).to eql 1
    end
    it 'should handle blank lines by ignoring them' do
      @build_results = SortedSet.new
      stdout = "# TypeError: cannot concatenate \'str\' and \'int\' objects\n\n# TypeError: cannot whatever \'str\' and \'int\' objects"
      process_python_results('/src/dir', '/build/dir', stdout, '', 0)
      expect(@build_results.length).to eql 2
    end
    it 'should read from stdout and stderr' do
      @build_results = SortedSet.new
      stdout = "# TypeError: cannot concatenate \'str\' and \'int\' objects"
      stderr = "# TypeError: cannot IMNOTSURE \'str\' and \'int\' objects"
      process_python_results('/src/dir', '/build/dir', stdout, stderr,0)
      expect(@build_results.length).to eql 2
    end
  end

  context 'when calling parse_package_names' do
    it 'should ignore empty lines' do
      message = ''
      response = parse_package_names(message)
      expect(response.length).to eql 0
    end
    it 'should get a valid package name from one line' do
      message = 'CPack: - package: abd generated.'
      response = parse_package_names(message)
      expect(response.length).to eql 1
    end
    it 'should get multiple valid package names' do
      message = "CPack: - package: abd generated.\nCPack: - package: zyx generated."
      response = parse_package_names(message)
      expect(response.length).to eql 2
    end
  end

  context 'when calling process_lcov_results' do
    it 'should properly parse an lcov response' do
      message = "Overall coverage rate:\n lines......: 67.9% (6 of 10 lines)\n functions..: 83.8% (12 of 36 functions)"
      response = process_lcov_results(message)
      expect(response.length).to eql 4
      expect(response[0]).to eql 10  # total lines
      expect(response[1]).to eql 6  # covered lines
      expect(response[2]).to eql 36  # total functions
      expect(response[3]).to eql 12  # covered functions
    end
  end

  context 'when calling process_cmake_results' do
    it 'should handle no data' do
      @build_results = SortedSet.new
      process_cmake_results('/src/dir', '/build/dir', '',0, false)
      expect(@build_results.length).to eql 0
    end
    it 'should match on a few different formats' do
      @build_results = SortedSet.new
      stderr = 'CPack Error: Hey there'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results = SortedSet.new
      stderr = 'CMake Error: Hey there'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results = SortedSet.new
      stderr = 'ERROR: Hey there'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results = SortedSet.new
      stderr = 'WARNING: Hey there'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results = SortedSet.new
      stderr = 'CMake Error at CMakeLists.txt:33 (d):'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results = SortedSet.new
      stderr = 'main.f90:32:'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results = SortedSet.new
      stderr = 'main.cc:32:'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
    end
    it 'should ignore blank lines' do
      @build_results = SortedSet.new
      stderr = "CPack Error: Hey there\n\nCPack Error: Hey there-ish"
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 2
    end
    it 'should handle odd long cmake messages' do
      @build_results = SortedSet.new
      stderr = "CMake Error at CMakeLists.txt:33 (d):\nI am on a second line"
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
    end
    it 'should handle another odd long cmake message' do
      @build_results = SortedSet.new
      stderr = "CMake Error at CMakeLists.txt:33 (d):\n "
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
    end
    it 'should keep context between two lines' do
      @build_results = SortedSet.new
      stderr = "CMake Error: Hey there\nI am on a second line"
      process_cmake_results('/src/dir', '/build/dir', stderr,0, false)
      expect(@build_results.length).to eql 1
      @build_results.each do |br|
        expect(br.message).to include 'there'
        expect(br.message).to include 'second'
      end
    end
    it 'should assign errors to package during packaging' do
      @package_results = SortedSet.new
      stderr = 'CPack Error: Hey there'
      process_cmake_results('/src/dir', '/build/dir', stderr,0, true)
      expect(@package_results.length).to eql 1
    end
  end

  # I'm not actually sure if we even use a Test.xml file but I'll test it anyway
  context 'when calling process_ctest_results' do
    it 'should process a Test.xml file with a run' do
      temp_dir = Dir.mktmpdir
      temp_file = File.join(temp_dir, "Test.xml")
      xml_content = <<-XML
<Site><Testing><Test>
 <Status>OK</Status>
 <Results>
  <Measurement><Value>[decent_ci:test_result:message] hello</Value></Measurement>
  <NamedMeasurement type="array">
   <Measurement><name>Exit Code</name><Value>23</Value></Measurement>
   <Measurement><name>Execution Time</name><Value>32</Value></Measurement>
  </NamedMeasurement>
 </Results>
</Test></Testing></Site>
      XML
      open(temp_file, 'w') { |f| f << xml_content }
      results, messages = process_ctest_results("/src/dir", "/build/dir", temp_dir)
      expect(results.length).to eql 1
      expect(messages.length).to eql 1
    end
    it 'should process a Test.xml file with just a notrun' do
      temp_dir = Dir.mktmpdir
      temp_file = File.join(temp_dir, "Test.xml")
      open(temp_file, 'w') { |f| f << "<Site><Testing><Test><Status>notrun</Status></Test></Testing></Site>" }
      process_ctest_results("/src/dir", "/build/dir", temp_dir)
    end
    it 'should return gracefully for missing folder' do
      results, messages = process_ctest_results("/src/dir", "/build/dir", "/folder/does/not/exist")
      expect(results).to be_nil
      expect(messages.length).to eql 0
    end
    it 'should process a full successful, no regression, test results file' do
      results, messages = process_ctest_results('', '', 'spec/resources/BaselineNoRegressions')
      expect(results.length).to eql 1370
      expect(messages.length).to eql 0
    end
    it 'should process a full successful, with regression, test results file' do
      results, messages = process_ctest_results('', '', 'spec/resources/BranchWithRegressions')
      expect(results.length).to eql 1646
      expect(messages.length).to eql 0
    end
    it 'should process doc build json error files in build/doc' do
      temp_dir = Dir.mktmpdir
      temp_build_dir = Dir.mktmpdir
      doc_build_dir = File.join(temp_build_dir, 'doc')
      Dir.mkdir(doc_build_dir)
      doc_build_error_file = File.join(doc_build_dir, 'something_errors.json')
      json_data = {
          "log_file_path": "/eplus/repos/forks/doc/engineering-reference/engineering-reference.log",
          "issues": [
              {
                  "severity": "WARNING",
                  "type": "Hyper reference undefined",
                  "locations": [
                      {
                          "file": "src/climate-sky-and-solar-shading-calculations/shading-module.tex",
                          "line": 176
                      }
                  ],
                  "message": " Hyper reference `surfacePropertylocalEnvironment' on page 205 undefined on input line 176.\n",
                  "label": "surfacePropertylocalEnvironment"
              },
              {
                  "severity": "WARNING",
                  "type": "Hyper reference undefined",
                  "locations": [
                      {
                          "file": "src/climate-sky-and-solar-shading-calculations/shading-module.tex",
                          "line": 177
                      }
                  ],
                  "message": " Hyper reference `schedulefileshading' on page 205 undefined on input line 177.\n",
                  "label": "schedulefileshading"
              },
              {
                  "severity": "WARNING",
                  "type": "Package hyperref",
                  "locations": [
                      {
                          "file": "src/demand-limiting.tex",
                          "line": 22
                      }
                  ],
                  "message": "Difference (2) between bookmark levels is greater (hyperref)                than one, level fixed on input line 22."
              }
          ]
      }
      json_content = JSON.dump(json_data)
      open(doc_build_error_file, 'w') { |f| f << json_content }
      results, messages = process_ctest_results("/src/dir", temp_build_dir, temp_dir)
      expect(results.length).to eql 3
        # expect(results[0].parsed_errors[0].linenumber).to eql 176
    end
  end
end
