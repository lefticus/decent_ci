require 'rspec'
require_relative '../lib/potentialbuild'
require_relative '../lib/resultsprocessor'

class PotentialBuildDummyRepo
  def name
    'repo_name'
  end
end

describe 'PotentialBuild Testing', :focus do
  include ResultsProcessor
  context 'when doing simple construction' do
    it 'should succeed at construction' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
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
      p = PotentialBuild.new(client, token, repo, tag_name, commit_sha, branch_name, author, release_url, release_assets, pull_id, pr_base_repo, pr_base_ref)
    end
  end
  context 'when calling needs_release_package' do
    it 'should base it on the analyze only flag' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
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
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      allow_any_instance_of(Octokit::Client).to receive(:repo).and_return(PotentialBuildDummyRepo.new)
      client = Octokit::Client.new(:access_token => 'abc')
      p = PotentialBuild.new(client, '', 'spec/resources', '', '', '', '', '', '', 0, '', '')
      src_dir = Dir.mktmpdir
      expect(p.checkout(src_dir)).to be_truthy
    end
  end
end

