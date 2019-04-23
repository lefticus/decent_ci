require 'rspec'
require_relative '../lib/cppcheck'
require_relative '../lib/runners'
require_relative '../lib/resultsprocessor'

describe 'CppCheck Testing' do
  include Cppcheck
  before do
    allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['a', 'b', 'c'])
    allow_any_instance_of(ResultsProcessor).to receive(:process_cppcheck_results).and_return(true)
  end
  context 'when running cppcheck' do
    it 'should return the value of the cppcheck results processor' do
      expect(cppcheck({}, {}, "/src/dir", "/build/dir")).to be_truthy
    end
    it 'should generate a good command line' do
      compiler = { :num_parallel_builds => 2, :compiler_extra_flags => "hello", :cppcheck_bin => "/usr/bin/cppcheck" }
      command_line = generate_command_line(compiler, "/src/dir")
      expect(command_line).to include 'cppcheck'
    end
  end
end
