# encoding: UTF-8 

require 'octokit'
require 'json'
require 'open3'
require 'pathname'
require 'active_support/core_ext/hash'
require 'find'
require 'logger'
require 'fileutils'
require 'ostruct'
require 'yaml'
require 'base64'

require_relative 'codemessage.rb'
require_relative 'testresult.rb'
require_relative 'potentialbuild.rb'

# Top level class that loads the list of potential builds from github
#
class Build
  def initialize(token, repository)
    @client = Octokit::Client.new(:access_token=>token)
    @token = token
    @repository = repository
    @user = @client.user
    @user.login
    @potential_builds = []
    @logger = Logger.new(STDOUT)
   end

  def query_releases
    releases = @client.releases(@repository)

    releases.each { |r|
      begin 
        @potential_builds << PotentialBuild.new(@client, @token, @repository, r.tag_name, nil, nil, r.url, r.assets, nil, nil, nil)
      rescue => e
        @logger.info("Skipping potential build: #{e.backtrace} #{r.tag_name}")
      end
    }
  end

  def query_branches
    # todo properly handle paginated results from github
    branches = @client.branches(@repository, :per_page => 100)

    branches.each { |b| 
      @logger.debug("Querying potential build: #{b.name}")
      begin 
        @potential_builds << PotentialBuild.new(@client, @token, @repository, nil, b.commit.sha, b.name, nil, nil, nil, nil, nil)
      rescue => e
        @logger.info("Skipping potential build: #{e.backtrace} #{b.name}")
      end
    }
  end

  # note, only builds 'external' pull_requests. Internal ones would have already
  # been built as a branch
  def query_pull_requests
    pull_requests = @client.pull_requests(@repository, :state=>"open")

    pull_requests.each { |p| 
      if p.head.repo.full_name == p.base.repo.full_name
        @logger.info("Skipping pullrequest originating from head repo");
      else
        begin 
          @potential_builds << PotentialBuild.new(@client, @token, p.head.repo.full_name, nil, p.head.sha, p.head.ref, nil, nil, p.number, p.base.repo.full_name, p.base.ref)
        rescue => e
          @logger.info("Skipping potential build: #{e.backtrace} #{p}")
        end
      end
    }
  end


  def potential_builds
    @potential_builds
  end
end



