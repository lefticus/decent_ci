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
require_relative 'github.rb'

# Top level class that loads the list of potential builds from github
#
class Build
  def initialize(token, repository, max_age)
    @client = Octokit::Client.new(:access_token=>token)
    @token = token
    @repository = repository
    @user = github_query(@client) { @client.user }
    github_query(@client) { @user.login }
    @potential_builds = []
    @max_age = max_age

    github_check_ratelimit(@client.last_response.headers);
   end

  def query_releases
    releases = github_query(@client) { @client.releases(@repository) }

    releases.each { |r|
      begin 
        days = (DateTime.now() - DateTime.parse(r.published_at.to_s)).round()
        if days <= @max_age
          @potential_builds << PotentialBuild.new(@client, @token, @repository, r.tag_name, nil, nil, r.author.login, r.url, r.assets, nil, nil, nil)
        else 
          $logger.info("Skipping potential build, it hasn't been updated in #{days} days; #{r.tag_name}");
        end
      rescue => e
        $logger.info("Skipping potential build: #{e} #{e.backtrace} #{r.tag_name}")
      end
    }
  end

  def query_branches
    # todo properly handle paginated results from github
    branches = github_query(@client) { @client.branches(@repository, :per_page => 100) }

    branches.each { |b| 
      $logger.debug("Querying potential build: #{b.name}")
      branch_details = github_query(@client) { @client.branch(@repository, b.name) }
      begin
        days = (DateTime.now() - DateTime.parse(branch_details.commit.commit.author.date.to_s)).round()
        if days <= @max_age
          login = "Unknown"
          if !branch_details.commit.author.nil?
            login = branch_details.commit.author.login
          else
            $logger.debug("Commit author is nil, getting login details from committer information")
            if !branch_details.commit.committer.nil?
              login = branch_details.commit.committer.login
            end
            $logger.debug("Login set to #{login}")
          end

          @potential_builds << PotentialBuild.new(@client, @token, @repository, nil, b.commit.sha, b.name, login, nil, nil, nil, nil, nil)
        else
          $logger.info("Skipping potential build, it hasn't been updated in #{days} days; #{b.name}");
        end
      rescue => e
        $logger.info("Skipping potential build: #{e} #{e.backtrace} #{b.name}")
      end
    }
  end

  # note, only builds 'external' pull_requests. Internal ones would have already
  # been built as a branch. Skipping of internal PR happens inside this function
  def query_pull_requests t_options
    pull_requests = github_query(@client) { @client.pull_requests(@repository, :state=>"open") }

    external_users = t_options[:external_users]
    trusted_branch = t_options[:trusted_branch]

    begin
      if trusted_branch.nil? || trusted_branch == ""
        file_content = Base64.decode64(github_query(client) { client.contents(@repository, :path=>".decent_ci-external_users.yaml") })
      else
        file_content = Base64.decode64(github_query(client) { 
          client.contents(@repository, { :path=>".decent_ci-external_users.yaml", :ref=>trusted_branch } ) 
        })
      end

      file_data = YAML.load(file_content)
      $logger.debug("Successfully loaded .decent_ci-external_users.yaml from '#{trusted_branch}'")
      file_data["external_users"].each { |x| external_users << Regexp.new(x) }
    rescue SyntaxError => e
      $logger.info("#{e.message} error while reading external_users file")
    rescue Psych::SyntaxError => e
      $logger.info("#{e.message} error while reading external_users file")
    rescue => e
      $logger.info("#{e.message} error while reading external_users file")
    end

    external_users.each{ |x| $logger.debug("Known external user: #{x}") }

    @pull_request_details = []


    pull_requests.each { |p| 

      issue = github_query(@client) { @client.issue(@repository, p.number) }

      $logger.debug("Issue loaded: #{issue}")


      notification_users = Set.new()

      if issue.assignee
        notification_users << issue.assignee.login
      end

      if p.user.login
        notification_users << p.user.login
      end

      aging_pull_requests_notification = true
      aging_pull_requests_numdays = 7

      begin
        pb = PotentialBuild.new(@client, @token, p.head.repo.full_name, nil, p.head.sha, p.head.ref, p.head.user.login, nil, nil, p.number, p.base.repo.full_name, p.base.ref)
        configed_notifications = pb.configuration.notification_recipients
        if !configed_notifications.nil?
          $logger.debug("Merging notifications user: #{configed_notifications}")
          notification_users.merge(configed_notifications)
        end

        aging_pull_requests_notification = pb.configuration.aging_pull_requests_notification
        aging_pull_requests_numdays = pb.configuration.aging_pull_requests_numdays

        if p.head.repo.full_name == p.base.repo.full_name
          $logger.info("Skipping pullrequest originating from head repo")
        else
          if external_users.any? { |x| x =~ p.head.user.login }
            @potential_builds << pb
          else
            $logger.info("Skipping pullrequest originating from unknown user #{p.head.user.login}")
          end
        end
      rescue => e
        $logger.info("Skipping potential build: #{e} #{e.backtrace} #{p}")
      end

      @pull_request_details << { :id => p.number, :creator => p.user.login, :owner => (issue.assignee ? issue.assignee.login : nil), :last_updated => issue.updated_at, :repo => @repository, :notification_users => notification_users, :aging_pull_requests_notification => aging_pull_requests_notification, :aging_pull_requests_numdays => aging_pull_requests_numdays }
    }
  end

  def get_pull_request_details
    @pull_request_details
  end

  def get_regression_base t_potential_build
    config = t_potential_build.configuration
    defined_baseline = config.send("regression_baseline_#{t_potential_build.branch_name}")

    default_baseline = config.regression_baseline_default
    default_baseline = "develop" if default_baseline.nil? && t_potential_build.branch_name != "develop" && t_potential_build.branch_name != "master"

    baseline = defined_baseline ? defined_baseline : default_baseline

    $logger.info("Baseline defined as: '#{baseline}' for branch '#{t_potential_build.branch_name}'")

    baseline = nil if baseline == t_potential_build.branch_name || baseline == ""

    $logger.info("Baseline refined to: '#{baseline}' for branch '#{t_potential_build.branch_name}'")

    if baseline.nil? || baseline == ""
      return nil
    end

    @potential_builds.each { |p|
      if p.branch_name == baseline
        return p
      end
    }

    return nil
  end

  def potential_builds
    return @potential_builds
  end

  def needs_daily_task(results_repo, results_path)
    begin 
      dateprefix = DateTime.now.utc.strftime("%F")
      document = 
<<-eos
---
title: #{dateprefix} Daily Task
tags: daily_task
date: #{DateTime.now.utc.strftime("%F %T")}
repository: #{@repository}
machine_name: #{Socket.gethostname}
machine_ip: #{Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address}
---

eos

      response = github_query(@client) { @client.create_contents(results_repo,
                                                          "#{results_path}/#{dateprefix}-DailyTaskRun",
                                                          "Commit daily task run file: #{dateprefix}-DailyTaskRun",
                                                          document) } 

      $logger.info("Daily task document sha: #{response.content.sha}")
      return true
    rescue => e
      $logger.info("Daily task file not created, skipping daily task")
      return false
    end

  end

  def client
    @client
  end


  def results_repositories
    s = Set.new()
    @potential_builds.each { |p|
      if !p.is_pull_request
        s << [p.configuration.repository, p.configuration.results_repository, p.configuration.results_path]
      end
    }
    return s
  end


end



