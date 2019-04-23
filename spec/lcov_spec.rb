require 'rspec'
require_relative '../lib/lcov'
require_relative '../lib/runners'
require_relative '../lib/resultsprocessor'

describe 'LCov Testing' do
  include Lcov
  before do
    allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['a', 'b', 'c'])
    allow_any_instance_of(ResultsProcessor).to receive(:process_lcov_results).and_return(true)
  end
  context 'when running lcov' do
    it 'should return the value of the lcov results processor' do
      expect(lcov({}, {}, "/build/dir")).to be_truthy
    end
    it 'should generate suitable command lines' do
      compiler = { :coverage_pass_limit => 3.14, :coverage_warn_limit => 2.72, :coverage_base_dir => "/base/dir" }
      command_line = generate_base_command_line(compiler, "/build/dir")
      expect(command_line).to include 'lcov'
      command_line = generate_filter_command_line("/build/dir")
      expect(command_line).to include 'filtered'
      command_line = generate_html_command_line(compiler, "/build/dir")
      expect(command_line).to include 'genhtml'
    end
  end
end
