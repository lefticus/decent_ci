require 'rspec'
require_relative '../lib/cmake'
require_relative '../lib/configuration'
require_relative '../lib/resultsprocessor'

class DummyRegressionBuild
  attr_reader :this_build_dir
  attr_reader :commit_sha
  def initialize(build_dir, sha)
    @this_build_dir = build_dir
    @commit_sha = sha
  end
end

describe 'CMake Testing' do
  include CMake
  include Configuration
  include ResultsProcessor

  context 'when calling cmake_build' do
    it 'should try to build a base release package' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      regression_dir = nil
      regression_baseline = nil
      @build_results = SortedSet.new
      args = CMakeBuildArgs.new('Debug', 'thisDeviceIDHere', true,)
      response = cmake_build(compiler,src_dir, build_dir, regression_dir, regression_baseline, args)
      expect(response).to be_truthy
    end
    it 'should try to build a release package with a target_arch key' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      compiler[:target_arch] = "63bit"
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      regression_dir = nil
      regression_baseline = nil
      @build_results = SortedSet.new
      args = CMakeBuildArgs.new('Debug', 'thisDeviceIDHere', true)
      response = cmake_build(compiler,src_dir, build_dir, regression_dir, regression_baseline, args)
      expect(response).to be_truthy
    end
    it 'should try to build a release without ccbin' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      compiler[:cc_bin] = nil
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      regression_dir = nil
      regression_baseline = nil
      @build_results = SortedSet.new
      args = CMakeBuildArgs.new('Debug', 'thisDeviceIDHere', true)
      response = cmake_build(compiler,src_dir, build_dir, regression_dir, regression_baseline, args)
      expect(response).to be_truthy
    end
    it 'should try to build a release with regressions' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      regression_dir = Dir.mktmpdir
      regression_baseline = DummyRegressionBuild.new('/dir/', 'abcd')
      @build_results = SortedSet.new
      args = CMakeBuildArgs.new('Debug', 'thisDeviceIDHere', true)
      response = cmake_build(compiler,src_dir, build_dir, regression_dir, regression_baseline, args)
      expect(response).to be_truthy
    end
  end
  context 'when calling cmake_package' do
    it 'should try to build a simple package' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      @package_results = SortedSet.new
      cmake_package(compiler, src_dir, build_dir, 'Debug')
    end
    it 'should try to build but fail with no package results' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(ResultsProcessor).to receive(:process_cmake_results).and_return(nil)
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      @package_results = SortedSet.new
      expect{ cmake_package(compiler, src_dir, build_dir, 'Debug') }.to raise_error RuntimeError
    end
    it 'should try to build and fail but with some package results' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(ResultsProcessor).to receive(:process_cmake_results).and_return(nil)
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      @package_results = SortedSet.new([1, 2])
      expect(cmake_package(compiler, src_dir, build_dir, 'Debug')).to be_nil
    end
    it 'should complete a build and return a proper name' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(ResultsProcessor).to receive(:process_cmake_results).and_return(true)
      allow_any_instance_of(ResultsProcessor).to receive(:parse_package_names).and_return(['hello'])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      @package_results = SortedSet.new([1, 2])
      response = cmake_package(compiler, src_dir, build_dir, 'Debug')
      expect(response.length).to eql 1
      expect(response[0]).to eql 'hello'
    end
  end
  context 'when calling cmake_test' do
    it 'should run a simple set of tests' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(ResultsProcessor).to receive(:process_cmake_results).and_return(true)
      allow_any_instance_of(ResultsProcessor).to receive(:process_ctest_results).and_return([[], []])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      @test_messages = []
      expect(cmake_test(compiler, src_dir, build_dir, 'Debug', true)).to be_truthy
    end
    it 'should run a simple set of tests and concatenate test_results' do
      allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['stdoutmsg', 'stderrmsg', 0])
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(ResultsProcessor).to receive(:process_cmake_results).and_return(true)
      allow_any_instance_of(ResultsProcessor).to receive(:process_ctest_results).and_return([[], []])
      @client = Octokit::Client.new(:access_token => 'abc')
      @config = load_configuration('spec/resources', 'abc', false)
      compiler = @config.compilers.first
      src_dir = Dir.mktmpdir
      build_dir = File.join(src_dir, 'build')
      @test_results = []
      @test_messages = []
      expect(cmake_test(compiler, src_dir, build_dir, 'Debug', true)).to be_truthy
    end
  end
end
