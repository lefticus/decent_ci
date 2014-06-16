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
        @potential_builds << PotentialBuild.new(@client, @token, @repository, r.tag_name, nil, nil, r.author.login, r.url, r.assets, nil, nil, nil)
      rescue => e
        @logger.info("Skipping potential build: #{e} #{e.backtrace} #{r.tag_name}")
      end
    }
  end

  def query_branches
    # todo properly handle paginated results from github
    branches = @client.branches(@repository, :per_page => 100)

    branches.each { |b| 
      @logger.debug("Querying potential build: #{b.name}")
      branch_details = @client.branch(@repository, b.name)
      begin 
        @potential_builds << PotentialBuild.new(@client, @token, @repository, nil, b.commit.sha, b.name, branch_details.commit.author.login, nil, nil, nil, nil, nil)
      rescue => e
        @logger.info("Skipping potential build: #{e} #{e.backtrace} #{b.name}")
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
          @potential_builds << PotentialBuild.new(@client, @token, p.head.repo.full_name, nil, p.head.sha, p.head.ref, p,head.user.login, nil, nil, p.number, p.base.repo.full_name, p.base.ref)
        rescue => e
          @logger.info("Skipping potential build: #{e} #{e.backtrace} #{p}")
        end
      end
    }
  end

  def get_regression_base t_potential_build
    if t_potential_build.branch_name == "master"
      return nil
    elsif t_potential_build.branch_name == "develop"
      @potential_builds.each { |p|
        if p.branch_name == "master"
          return p
        end
      }
      return nil
    else 
      @potential_builds.each { |p|
        if p.branch_name == "develop"
          return p
        end
      }
      return nil
    end
  end

  def potential_builds
    @potential_builds
  end
end



