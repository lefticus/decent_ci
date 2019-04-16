require 'rspec'
require_relative '../lib/cmake'
require_relative '../lib/configuration'

describe 'CMake Testing' do
  include CMake
  include Configuration

  context 'when calling cmake_build' do
    it 'should try to build', :focus do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])

      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first

      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')

      regression_dir = Dir.mktmpdir
      regression_baseline = nil

      @build_results = SortedSet.new

      args = CMakeBuildArgs.new('Debug', 'thisDeviceIDHere', true, true)

      response = cmake_build(compiler,src_dir, build_dir, regression_dir, regression_baseline, args)
      expect(response).to be_truthy
    end
  end
end

