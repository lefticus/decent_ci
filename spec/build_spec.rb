require 'octokit'
require 'rspec'

require_relative '../lib/decent_exceptions'
require_relative '../lib/potentialbuild'
require_relative '../lib/build'

class DummyResponse2
  def headers
    {'a' => true}
  end
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
  def initialize(published_date, should_throw = false)
    @this_published_at = published_date
    @should_throw = should_throw
  end
  def author
    DummyUser.new(-1)
  end
  def published_at
    if @should_throw
      raise CannotMatchCompiler, 'hey'
    end
    @this_published_at
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
  attr_reader :name
  def initialize(published_date, name, use_committer_login = false, should_throw = false)
    @name = name
    @published_date = published_date
    @use_committer_login = use_committer_login
    @should_throw = should_throw
  end
  def commit
    if @should_throw
      raise CannotMatchCompiler, "Again!"
    end
    DummyCommit1.new(@published_date, @use_committer_login)
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
  def initialize(repo_name, should_throw)
    @full_name = repo_name
    @should_throw = should_throw
  end
  def repo
    DummyRepo.new(@full_name)
  end
  def user
    DummyUser.new(-1)
  end
  def sha
    if @should_throw
      raise CannotMatchCompiler, 'World'
    end
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
  def initialize(pr_number, external, bad_base = false, should_throw = false)
    @number = pr_number
    @assignee = nil
    @user = DummyUser.new(-1)
    @updated_at = 0
    if external
      @head = DummyPRHead.new('external', should_throw)
    else
      @head = DummyPRHead.new('origin', should_throw)
    end
    if bad_base
      @base = nil
    else
      @base = DummyPRHead.new('origin', should_throw)
    end
  end
end

class DummyContentResponse
  def content
    DummyCommit1.new(1, 2)
  end
end

class DummyClient2
  attr_accessor :content_response
  def initialize
    t_base = Time.now
    t_base.utc
    t_too_old = t_base - 60*60*24*40
    t_recent = t_base - 60*60*24*2
    @my_releases = [
      DummyRelease.new(t_too_old),
      DummyRelease.new(t_recent),
      DummyRelease.new(-1),
      DummyRelease.new(t_recent, true)
    ]
    @my_branches = [
      DummyBranch.new(t_too_old, 'a'),
      DummyBranch.new(t_recent, 'b'),
      DummyBranch.new(-1, 'c'),
      DummyBranch.new(t_recent, 'd', true),
      DummyBranch.new(t_recent, 'e', false, true),
      DummyBranch.new(t_recent, 'fixes-#191-dialog')
    ]
    @my_prs = [
      DummyPR.new(1, true, false),
      DummyPR.new(2, false, false),
      DummyPR.new(3, true, true),
      DummyPR.new(4, true, false, true)
    ]
    @content_response = DummyContentResponse.new
  end
  def last_response
    return DummyResponse2.new
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
  def create_contents(repo_name, file_path, commit_msg, document)
    @content_response
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
  def regression_baseline_branch
    nil  # a different name here would allow a branch to target a different baseline
  end
  def regression_baseline_default
    'develop'
  end
  def repository
    'dummy'
  end
  def results_repository
    'dummy2'
  end
  def results_path
    'results_path'
  end
end

class DummyPotentialBuild
  attr_reader :branch_name
  attr_accessor :pr
  def initialize(branch_name)
    @branch_name = branch_name
  end
  def configuration
    DummyConfiguration.new
  end
  def pull_request?
    @pr
  end
end

describe 'Build Testing' do
  context 'when calling query_releases' do
    it 'should include builds that are valid and new' do
      # default age is 30
      c = DummyClient2.new
      allow(Octokit::Client).to receive(:new).and_return(c)
      allow(PotentialBuild).to receive(:new).and_return(true)
      b = Build.new('abcdef', 'spec/resources', 10)
      expect(b.client.releases('').length).to eql 4 # should have three total releases
      b.query_releases
      expect(b.potential_builds.length).to eql 1 # but only one is valid and new enough to build
    end
  end
  context 'when calling query_branches' do
    it 'should include branches that are valid and new' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      allow(PotentialBuild).to receive(:new).and_return(true)
      b = Build.new('abcdef', 'spec/resources', 10)
      expect(b.client.branches('', 1).length).to eql 5 # should have four total total branches
      b.query_branches
      expect(b.potential_builds.length).to eql 2 # but only two are valid and new enough to build
    end
  end
  context 'when calling query_pull_requests' do
    it 'should include PRs that are valid and new' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      allow(PotentialBuild).to receive(:new).and_return(DummyPotentialBuild.new('dummy'))
      b = Build.new('abcdef', 'spec/resources', 10)
      expect(b.client.pull_requests('', 1).length).to eql 4
      b.query_pull_requests
      expect(b.potential_builds.length).to eql 1 # only 1 is valid and from a remote repo
    end
  end
  context 'when calling get_regression_base' do
    it 'should return valid regression base' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      b = Build.new('abc', 'spec/resources', 10)
      b.potential_builds = [DummyPotentialBuild.new('develop')]
      d = DummyPotentialBuild.new('branch')
      response = b.get_regression_base(d)
      expect(response).not_to be_nil
    end
    it 'should return nil if no valid regression base' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      b = Build.new('abc', 'spec/resources', 10)
      d = DummyPotentialBuild.new('branch')
      response = b.get_regression_base(d)
      expect(response).to be_nil
    end
  end
  context 'when calling needs_daily_task' do
    it 'should just do it' do
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      b = Build.new('abc', 'spec/resources', 10)
      expect(b.needs_daily_task('repo', 'results')).to be_truthy
    end
    it 'should fail gracefully when there is a problem' do
      d = DummyClient2.new
      d.content_response= nil
      allow(Octokit::Client).to receive(:new).and_return(d)
      b = Build.new('abc', 'spec/resources', 10)
      expect(b.needs_daily_task('repo', 'results')).to be_falsey
    end 
  end
  context 'when calling results_repositories' do
    it 'should get all potential build results repos' do
      d = DummyPotentialBuild.new('a')
      d.pr = true
      d2 = DummyPotentialBuild.new('b')
      d.pr = false
      d3 = DummyPotentialBuild.new('c')
      d.pr = true
      allow(Octokit::Client).to receive(:new).and_return(DummyClient2.new)
      b = Build.new('abc', 'spec/resources', 10)
      b.potential_builds = [d, d2, d3]
      expect(b.potential_builds.length).to eql 3
      expect(b.results_repositories.length).to eql 1 # two are valid, but they are duplicate, so only one results
    end
  end
end
