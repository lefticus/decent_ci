require 'octokit'
require 'rspec'
require_relative '../lib/potentialbuild'
require_relative '../lib/build'

class DummyResponse
end

class DummyUser
  attr_reader :date
  def initialize(published_date)
    @date = published_date
  end
  def login
    true
  end
end

class DummyRelease
  attr_reader :published_at
  def initialize(published_date)
    @published_at = published_date
  end
  def author
    DummyUser.new(-1)
  end
  def tag_name
    'tag'
  end
  def url
    'http://dummy'
  end
  def assets
    ['stuff']
  end
end

class DummyCommit2
  attr_reader :author
  def initialize(published_date)
    @author = DummyUser.new(published_date)
  end
end

class DummyCommit1
  attr_reader :commit
  attr_reader :author
  attr_reader :committer
  def initialize(published_date, use_committer_login)
    @commit = DummyCommit2.new(published_date)
    if use_committer_login
      @author = nil
      @committer = DummyUser.new(published_date)
    else
      @author = DummyUser.new(published_date)
      @committer = nil
    end
  end
  def sha
    'abc123'
  end
end

class DummyBranch
  attr_reader :commit
  attr_reader :name
  def initialize(published_date, name, use_committer_login = false)
    @name = name
    @commit = DummyCommit1.new(published_date, use_committer_login)
  end
end

class DummyRepo
  attr_reader :full_name
  def initialize(repo_name)
    @full_name = repo_name
  end
end

class DummyPRHead
  attr_reader :full_name
  def initialize(repo_name)
    @full_name = repo_name
  end
  def repo
    DummyRepo.new(@full_name)
  end
  def user
    DummyUser.new(-1)
  end
  def sha
    'abdc'
  end
  def ref
    '123'
  end
end

class DummyPR
  attr_reader :number
  attr_reader :assignee
  attr_reader :user
  attr_reader :updated_at
  attr_reader :head
  attr_reader :base
  def initialize(pr_number, external, bad_base = false)
    @number = pr_number
    @assignee = nil
    @user = DummyUser.new(-1)
    @updated_at = 0
    if external
      @head = DummyPRHead.new('external')
    else
      @head = DummyPRHead.new('origin')
    end
    if bad_base
      @base = nil
    else
      @base = DummyPRHead.new('origin')
    end
  end
end

class DummyClient2
  def initialize
    t_base = Time.now
    t_base.utc
    t_too_old = t_base - 60*60*24*40
    t_recent = t_base - 60*60*24*2
    @my_releases = [DummyRelease.new(t_too_old), DummyRelease.new(t_recent), DummyRelease.new(-1)]
    @my_branches = [DummyBranch.new(t_too_old, 'a'), DummyBranch.new(t_recent, 'b'), DummyBranch.new(-1, 'c'), DummyBranch.new(t_recent, 'd', true)]
    @my_prs = [DummyPR.new(1, true), DummyPR.new(2, false), DummyPR.new(3, true, true) ]
  end
  def last_response
    return DummyResponse.new
  end
  def user
    DummyUser.new(-1)
  end
  def releases(repo_name)
    @my_releases
  end
  def branches(repo_name, per_page)
    @my_branches
  end
  def branch(repo_name, branch_name)
    @my_branches.select { |b| b.name == branch_name }.first
  end
  def pull_requests(repo_name, open_state)
    @my_prs
  end
  def issue(repo_name, pr_number)
    @my_prs.select { |pr| pr.number == pr_number }.first
  end
end

class DummyConfiguration
  def notification_recipients
    []
  end
  def aging_pull_requests_notification
    false
  end
  def aging_pull_requests_numdays
    14
  end
end

class DummyPotentialBuild
  def configuration
    DummyConfiguration.new
  end
end

describe 'Build Testing', :focus do
  context 'when calling query_releases' do
    it 'should include builds that are valid and new' do
      # default age is 30
      c = DummyClient2.new
      allow(Octokit::Client).to receive(:new).and_return(c)
      allow(PotentialBuild).to receive(:new).and_return(true)
      b = Build.new('abcdef', 'spec/resources', 10)
      expect(b.client.releases('').length).to eql 3 # should have three total releases
      b.query_releases
      expect(b.potential_builds.length).to eql 1 # but only one is valid and new enough to build
    end
  end
  context 'when calling query_branches' do
    it 'should include branches that are valid and new' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      allow(PotentialBuild).to receive(:new).and_return(true)
      b = Build.new('abcdef', 'spec/resources', 10)
      expect(b.client.branches('', 1).length).to eql 4 # should have four total total branches
      b.query_branches
      expect(b.potential_builds.length).to eql 2 # but only two are valid and new enough to build
    end
  end
  context 'when calling query_pull_requests' do
    it 'should include PRs that are valid and new' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      allow(PotentialBuild).to receive(:new).and_return(DummyPotentialBuild.new)
      b = Build.new('abcdef', 'spec/resources', 10)
      expect(b.client.pull_requests('', 1).length).to eql 3
      b.query_pull_requests
      expect(b.potential_builds.length).to eql 1 # only 1 is valid and from a remote repo
    end
  end
end

