# frozen_string_literal: true

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
class Build
  attr_reader :client
  attr_reader :potential_builds
  attr_reader :pull_request_details

  def initialize(token, repository, max_age)
    @client = Octokit::Client.new(:access_token => token)
    @token = token
    @repository = repository
    @user = github_query(@client) { @client.user }
    github_query(@client) { @user.login }
    @potential_builds = []
    @max_age = max_age
    github_check_rate_limit(@client.last_response.headers)
  end

  def query_releases
    releases = github_query(@client) { @client.releases(@repository) }

    releases.each do |r|
      begin
        days = (DateTime.now - DateTime.parse(r.published_at.to_s)).round
        if days <= @max_age
          @potential_builds << PotentialBuild.new(@client, @token, @repository, r.tag_name, nil, nil, r.author.login, r.url, r.assets, nil, nil, nil)
        else
          $logger.info("Skipping potential build, it hasn't been updated in #{days} days; #{r.tag_name}")
        end
      rescue => e
        $logger.info("Skipping potential build: #{e} #{e.backtrace} #{r.tag_name}")
      end
    end
  end

  def query_branches
    # TODO: properly handle paginated results from github
    branches = github_query(@client) { @client.branches(@repository, :per_page => 100) }

    branches.each do |b|
      $logger.debug("Querying potential build: #{b.name}")
      branch_details = github_query(@client) { @client.branch(@repository, b.name) }
      begin
        days = (DateTime.now - DateTime.parse(branch_details.commit.commit.author.date.to_s)).round
        if days <= @max_age
          login = 'Unknown'
          if !branch_details.commit.author.nil?
            login = branch_details.commit.author.login
          else
            $logger.debug('Commit author is nil, getting login details from committer information')
            login = branch_details.commit.committer.login unless branch_details.commit.committer.nil?

            $logger.debug("Login set to #{login}")
          end

          @potential_builds << PotentialBuild.new(@client, @token, @repository, nil, b.commit.sha, b.name, login, nil, nil, nil, nil, nil)
        else
          $logger.info("Skipping potential build, it hasn't been updated in #{days} days; #{b.name}")
        end
      rescue => e
        $logger.info("Skipping potential build: #{e} #{e.backtrace} #{b.name}")
      end
    end
  end

  # note, only builds 'external' pull_requests. Internal ones would have already
  # been built as a branch
  def query_pull_requests
    pull_requests = github_query(@client) { @client.pull_requests(@repository, :state => 'open') }

    @pull_request_details = []

    pull_requests.each do |p|
      issue = github_query(@client) { @client.issue(@repository, p.number) }

      $logger.debug("Issue loaded: #{issue}")

      notification_users = Set.new

      notification_users << issue.assignee.login if issue.assignee

      notification_users << p.user.login if p.user.login

      aging_pull_requests_notify = true
      aging_pull_requests_num_days = 7

      begin
        pb = PotentialBuild.new(@client, @token, p.head.repo.full_name, nil, p.head.sha, p.head.ref, p.head.user.login, nil, nil, p.number, p.base.repo.full_name, p.base.ref)
        configured_notifications = pb.configuration.notification_recipients
        unless configured_notifications.nil?
          $logger.debug("Merging notifications user: #{configured_notifications}")
          notification_users.merge(configured_notifications)
        end

        aging_pull_requests_notify = pb.configuration.aging_pull_requests_notification
        aging_pull_requests_num_days = pb.configuration.aging_pull_requests_numdays

        if p.head.repo.full_name == p.base.repo.full_name
          $logger.info('Skipping pull-request originating from head repo')
        else
          @potential_builds << pb
        end
      rescue => e
        $logger.info("Skipping potential build: #{e} #{e.backtrace} #{p}")
      end

      @pull_request_details << {
        :id => p.number,
        :creator => p.user.login,
        :owner => (issue.assignee ? issue.assignee.login : nil),
        :last_updated => issue.updated_at,
        :repo => @repository,
        :notification_users => notification_users,
        :aging_pull_requests_notification => aging_pull_requests_notify,
        :aging_pull_requests_numdays => aging_pull_requests_num_days
      }
    end
  end

  def get_regression_base(t_potential_build)
    config = t_potential_build.configuration
    defined_baseline = config.send("regression_baseline_#{t_potential_build.branch_name}")

    default_baseline = config.regression_baseline_default
    default_baseline = 'develop' if default_baseline.nil? && t_potential_build.branch_name != 'develop' && t_potential_build.branch_name != 'master'

    baseline = defined_baseline || default_baseline

    $logger.info("Baseline defined as: '#{baseline}' for branch '#{t_potential_build.branch_name}'")

    baseline = nil if [t_potential_build.branch_name, ''].include? baseline

    $logger.info("Baseline refined to: '#{baseline}' for branch '#{t_potential_build.branch_name}'")

    return nil if baseline.nil? || baseline == ''

    @potential_builds.each do |p|
      # TODO: Protect other fork develop branches from inadvertently becoming the baseline branch
      return p if p.branch_name == baseline
    end

    nil
  end

  def needs_daily_task(results_repo, results_path)
    dateprefix = DateTime.now.utc.strftime('%F')
    document =
      <<-HEADER
---
title: #{dateprefix} Daily Task
tags: daily_task
date: #{DateTime.now.utc.strftime('%F %T')}
repository: #{@repository}
machine_name: #{Socket.gethostname}
machine_ip: #{Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address}
---

      HEADER

    response = github_query(@client) do
      @client.create_contents(
        results_repo,
        "#{results_path}/#{dateprefix}-DailyTaskRun",
        "Commit daily task run file: #{dateprefix}-DailyTaskRun",
        document
      )
    end

    $logger.info("Daily task document sha: #{response.content.sha}")
    true
  rescue
    $logger.info('Daily task file not created, skipping daily task')
    false
  end

  def results_repositories
    s = Set.new
    @potential_builds.each do |p|
      s << [p.configuration.repository, p.configuration.results_repository, p.configuration.results_path] unless p.pull_request?
    end
    s
  end
end
