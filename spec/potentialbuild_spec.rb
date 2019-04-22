require 'rspec'
require_relative '../lib/cppcheck'
require_relative '../lib/custom_check'
require_relative '../lib/potentialbuild'
require_relative '../lib/resultsprocessor'

class PotentialBuildDummyRepo
  def name
    'repo_name'
  end
end

class PotentialBuildNamedDummy
  attr_reader :name
  def initialize(this_name)
    @name = this_name
  end
end

describe 'PotentialBuild Testing' do
  include ResultsProcessor
  include Cppcheck
  include CustomCheck
  context 'when doing simple construction' do
    it 'should succeed at construction' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      token = 'abc'
      repo = 'spec/resources'
      tag_name = ''
      commit_sha = 'abc123'
      branch_name = 'feature'
      author = 'octokat'
      release_url = nil
      release_assets = nil
      pull_id = 32
      pr_base_repo = nil
      pr_base_ref = nil
      PotentialBuild.new(client, token, repo, tag_name, commit_sha, branch_name, author, release_url, release_assets, pull_id, pr_base_repo, pr_base_ref)
    end
  end
  context 'when calling needs_release_package' do
    it 'should base it on the analyze only flag' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      expect(p.needs_release_package({:analyze_only => true})).to be_falsey
      expect(p.needs_release_package({})).to be_truthy # defaults to true if no key
      expect(p.needs_release_package({:analyze_only => false})).to be_truthy
    end
  end
  context 'when calling checkout' do
    before do
      expect_any_instance_of(ResultsProcessor).to receive(:run_scripts).with(anything, instance_of(Array)).and_return(['stdout', 'stderr', 0])
    end
    it 'should succeed' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', nil, '', '')
      src_dir = Dir.mktmpdir
      expect(p.checkout(src_dir)).to be_truthy
    end
    it 'should succeed for a pull request' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 1, '', '')
      src_dir = Dir.mktmpdir
      expect(p.checkout(src_dir)).to be_truthy
    end
  end
  context 'when calling do_coverage' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      @p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
    end
    it 'should quit gracefully if not doing coverage' do
      expect(@p.do_coverage({})).to be_nil
    end
    it 'should do coverage successfully' do
      allow_any_instance_of(Lcov).to receive(:lcov).and_return([1, 2, 3, 4])
      expect_any_instance_of(ResultsProcessor).to receive(:run_scripts).with(anything, instance_of(Array)).and_return(['out_url', 'stderr', 0])
      expect(@p.do_coverage({:coverage_enabled => true, :coverage_s3_bucket => 'bucket'})).to include 'out_url'
    end
  end
  context 'when calling do_upload' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      @p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
    end
    it 'should quit gracefully if not doing upload' do
      expect(@p.do_upload({})).to be_nil
    end
    it 'should do upload successfully' do
      expect_any_instance_of(ResultsProcessor).to receive(:run_scripts).with(anything, instance_of(Array)).and_return(['out_url', 'stderr', 0])
      expect(@p.do_upload({:s3_upload => true, :coverage_s3_bucket => 'bucket'})).to include 'out_url'
    end
  end
  context 'when calling do_package' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      @client = Octokit::Client.new(:access_token => 'abc')
    end
    it 'should quit gracefully if not doing packaging for multiple reasons' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', nil, '', 0, '', '')
      expect(p.do_package({}, nil)).to be_nil  # if it's not a release build then don't try to build it
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', 'REL_URL', '', 0, '', '')
      expect(p.do_package({:analyze_only => true}, nil)).to be_nil  # analyze_only essentially means no release
      expect(p.do_package({:analyze_only => false, :skip_packaging => true}, nil)).to be_nil  # skip_packaging overrides other flags
    end
    it 'should do packaging successfully' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', 'REL_URL', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:do_build).and_return(nil)
      allow_any_instance_of(PotentialBuild).to receive(:cmake_package).and_return('package_location')
      expect(p.do_package({:analyze_only => false}, nil)).to include 'package_location'
    end
    it 'should raise an exception if cmake_package fails' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', 'REL_URL', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:do_build).and_return(nil)
      allow_any_instance_of(PotentialBuild).to receive(:cmake_package).and_raise('Uh oh')
      expect{ p.do_package({:analyze_only => false}, nil) }.to raise_error RuntimeError
    end
  end
  context 'when calling do_build' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      @client = Octokit::Client.new(:access_token => 'abc')
    end
    it 'should call custom check if it is trying to run custom checks' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:checkout).and_return(true)
      expect_any_instance_of(CustomCheck).to receive(:custom_check).and_return(nil)
      p.do_build({:name => "custom_check"}, nil)
    end
    it 'should call cppcheck if it is trying to run cppchecks' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:checkout).and_return(true)
      expect_any_instance_of(Cppcheck).to receive(:cppcheck).and_return(nil)
      p.do_build({:name => "cppcheck"}, nil)
    end
    it 'should call cmake_build if it is trying to run any other compilers' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:checkout).and_return(true)
      expect_any_instance_of(PotentialBuild).to receive(:cmake_build).and_return(nil)
      p.do_build({:name => "OTHER"}, nil)
    end
  end
  context 'when calling do_test' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      @client = Octokit::Client.new(:access_token => 'abc')
    end
    it 'should just build and return quietly for non-cmake builds' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:do_build).and_return(true)
      p.do_test({:name => "custom_check"}, nil) # just succeed
    end
    it 'should build and run cmake tests when appropriate' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:do_build).and_return(true)
      expect_any_instance_of(PotentialBuild).to receive(:cmake_test).and_return(nil)
      p.do_test({:name => "gcccc"}, nil)
    end
    it 'should respond to ENV for skipping tests' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      allow_any_instance_of(PotentialBuild).to receive(:do_build).and_return(true)
      ENV['DECENT_CI_SKIP_TEST'] = 'Y'
      p.do_test({:name => "gcccc"}, nil)  # should just return
      ENV.delete('DECENT_CI_SKIP_TEST')
    end
  end
  context 'when calling next_build' do
    it 'should reset attributes' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      p.set_as_baseline
      expect(p.this_src_dir).to include 'baseline'
      p.next_build
      expect(p.failure).to be_falsey
      expect(p.this_src_dir).to include 'branch'
    end
  end
  context 'when calling needs_regression_test' do
    it 'should skip it for several flags' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      expect(p.needs_regression_test({:analyze_only => true, :skip_regression => false})).to be_falsey
      expect(p.needs_regression_test({:analyze_only => false, :skip_regression => true})).to be_falsey
      ENV['DECENT_CI_SKIP_REGRESSIONS'] = 'Y'
      expect(p.needs_regression_test({:analyze_only => false, :skip_regression => false})).to be_falsey
      ENV.delete('DECENT_CI_SKIP_REGRESSIONS')
    end
    it 'should run it when things are just right' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      expect(p.needs_regression_test({:analyze_only => false, :skip_regression => false})).to be_truthy
    end
  end
  context 'when calling parse_call_grind' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      @p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
    end
    it 'should properly parse a callgrind file' do
      dir = Dir.mktmpdir
      call_grind_file = File.join(dir, 'callgrind.out')
      output_content = <<-GRIND
# callgrind format
events: Instructions

fl=file1.c
fn=main
16 20
cfn=func1
calls=1 50
16 400
cfi=file2.c
cfn=func2
calls=3 20
16 400

fn=func1
51 100
cfi=file2.c
cfn=func2
calls=2 20
51 300

fl=file2.c
fn=func2
20 700
      GRIND
      open(call_grind_file, 'w') { |f| f << output_content }
      response = @p.parse_call_grind(dir, call_grind_file)
      expect(response['data'].length).to eql 2
    end
  end
  context 'when calling needs_run' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      @p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
    end
    it 'should always need to run for test runs' do
      @p.test_run = true
      expect(@p.needs_run({})).to be_truthy
    end
    it 'should need to run if no matching files are found' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('a'), PotentialBuildNamedDummy.new('b')])
      expect(@p.needs_run({})).to be_truthy
    end
    it 'should not need to run if a matching file is found' do
      anticipated_name = @p.results_file_name({})
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new(anticipated_name)])
      expect(@p.needs_run({})).to be_falsey
    end
  end
  context 'when calling this_branch_folder' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      @client = Octokit::Client.new(:access_token => 'abc')
    end
    it 'should use the tag name for tagged builds' do
      p = PotentialBuild.new(@client, '', 'spec/resources', 'ABCDEF', '', 'branch', '', '', '', 0, '', '')
      expect(p.this_branch_folder).to include 'ABCDEF'
    end
    it 'should use the branch name for non-tagged builds' do
      p = PotentialBuild.new(@client, '', 'spec/resources', '', '', 'branch', '', '', '', 0, '', '')
      expect(p.this_branch_folder).to include 'branch'
    end
  end
  context 'when calling small attribute functions' do
    before do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([PotentialBuildNamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      @p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
    end
    it 'get_src_dir should make a selection based on baseline mode' do
      expect(@p.this_src_dir).to include 'branch'
      @p.set_as_baseline
      expect(@p.this_src_dir).to include 'baseline'
    end
    it 'this_regression_dir just return a clone-regression dir name' do
      expect(@p.this_regression_dir).to include 'regression'
    end
    it 'device_tag should return a string with optional debug tag' do
      expect(@p.device_tag({:build_tag => 'hello', :build_type => 'Release'})).not_to include 'Release'
      expect(@p.device_tag({:build_tag => 'hello', :build_type => 'Debug'})).to include 'Debug'
      expect(@p.device_tag({:build_tag => 'hello', :build_type => 'RelWithDebInfo'})).to include 'RelWithDebInfo'
    end
    it 'device_tag should return a string with optional debug tag' do
      expect(@p.device_tag({:build_tag => 'hello', :build_type => 'Release'})).not_to include 'Release'
      expect(@p.device_tag({:build_tag => 'hello', :build_type => 'Debug'})).to include 'Debug'
      expect(@p.device_tag({:build_tag => 'hello', :build_type => 'RelWithDebInfo'})).to include 'RelWithDebInfo'
    end
    it 'descriptive_string should just return a string' do
      expect(@p.descriptive_string).to be_instance_of String
    end
    it 'device_id should just return a string' do
      expect(@p.device_id({})).to be_instance_of String
    end
    it 'build_base_name should just return a string' do
      expect(@p.build_base_name({})).to be_instance_of String
    end
    it 'results_file_name should just return a string' do
      expect(@p.results_file_name({})).to be_instance_of String
    end
    it 'short_build_base_name should just return a string' do
      expect(@p.short_build_base_name({})).to be_instance_of String
    end
    it 'boolean flag functions should return booleans' do
      expect(@p.release?).to be_in([true, false])
      expect(@p.pull_request?).to be_in([true, false])
    end
    it 'compilers should just get compilers from configuration' do
      @p.configuration.compilers = 'hello'
      expect(@p.compilers).to eql 'hello'
    end
    it 'running_extra_tests should only be true in specific conditions' do
      expect(@p.running_extra_tests).to be_falsey
      client = Octokit::Client.new(:access_token => 'abc')
      @p = PotentialBuild.new(client, '', 'spec/resources', '', '', 'abc', '', '', '', 0, '', '')
      expect(@p.running_extra_tests).to be_falsey
      @p.configuration.extra_tests_branches = ['abc'] # with a test on this branch name, it should be truthy
      expect(@p.running_extra_tests).to be_truthy
    end
  end
end

