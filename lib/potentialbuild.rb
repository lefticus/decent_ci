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
require 'socket'

require_relative 'codemessage.rb'
require_relative 'testresult.rb'
require_relative 'cmake.rb'
require_relative 'configuration.rb'
require_relative 'resultsprocessor.rb'
require_relative 'cppcheck.rb'
require_relative 'github.rb'


## Contains the logic flow for executing builds and parsing results
class PotentialBuild
  include CMake
  include Configuration
  include ResultsProcessor
  include Cppcheck

  attr_reader :tag_name
  attr_reader :commit_sha
  attr_reader :branch_name

  def initialize(client, token, repository, tag_name, commit_sha, branch_name, author, release_url, release_assets, 
                 pull_id, pull_request_base_repository, pull_request_base_ref)
    @client = client
    @config = load_configuration(repository, (tag_name.nil? ? commit_sha : tag_name), !release_url.nil?)
    @config.repository_name = github_query(@client) { @client.repo(repository).name }
    @config.repository = repository
    @config.token = token
    @repository = repository
    @tag_name = tag_name
    @commit_sha = commit_sha
    @branch_name = branch_name
    @release_url = release_url
    @release_assets = release_assets
    @author = author

    @buildid = @tag_name ? @tag_name : @commit_sha
    @refspec = @tag_name ? @tag_name : @branch_name

    @pull_id = pull_id
    @pull_request_base_repository = pull_request_base_repository
    @pull_request_base_ref = pull_request_base_ref

    @short_buildid = get_short_form(@tag_name) ? get_short_form(@tag_name) : @commit_sha[0..9]

    @buildid = "#{@buildid}-PR#{@pull_id}" if !@pull_id.nil?

    @short_buildid = "#{@short_buildid}-PR#{@pull_id}" if !@pull_id.nil?

    @created_dirs = []
    @created_regression_dirs = []
    @package_location = nil
    @test_results = nil
    @build_results = SortedSet.new()
    @package_results = SortedSet.new()
    @dateprefix = nil
    @failure = nil
    @test_run = false
    @build_time = nil
    @test_time = nil
    @install_time = nil
    @package_time = nil
  end

  def compilers
    return @config.compilers
  end


  def set_test_run new_test_run
    @test_run = new_test_run
  end

  def descriptive_string
    return "#{@commit_sha} #{@branch_name} #{@tag_name} #{@buildid}"
  end

  def is_release
    return !@release_url.nil?
  end

  def is_pull_request
    return !@pull_id.nil?
  end

  def pull_request_issue_id
    return @pull_id
  end

  def running_extra_tests
    $logger.warn("Checking if running_extra_tests on branch: #{@branch_name} extra tests branches #{@config.extra_tests_branches}")
    if !@branch_name.nil? && !@config.extra_tests_branches.nil? && @config.extra_tests_branches.count(@branch_name) != 0
      return true
    else
      return false
    end

  end

  # originally from https://gist.github.com/lpar/1032297
  # runs a specified shell command in a separate thread.
  # If it exceeds the given timeout in seconds, kills it.
  # Returns any output produced by the command (stdout or stderr) as a String.
  # Uses Kernel.select to wait up to the tick length (in seconds) between 
  # checks on the command's status
  #
  # If you've got a cleaner way of doing this, I'd be interested to see it.
  # If you think you can do it with Ruby's Timeout module, think again.
  def run_with_timeout(env, command, timeout=60*60*4, tick=2)
    out = ""
    err = ""
    begin
      # Start task in another thread, which spawns a process
      stdin, stdout, stderr, thread = Open3.popen3(env, command)
      # Get the pid of the spawned process
      pid = thread[:pid]
      start = Time.now

      while (Time.now - start) < timeout and thread.alive?
        # Wait up to `tick` seconds for output/error data
        rs, = Kernel.select([stdout, stderr], nil, nil, tick)
        # Try to read the data
        begin
          if !rs.nil?
            rs.each { |r|
              if r == stdout
                out << stdout.read_nonblock(4096)
              elsif r == stderr 
                err << stderr.read_nonblock(4096)
              end
            }
          end

        rescue IO::WaitReadable
          # A read would block, so loop around for another select
        rescue EOFError
          # Command has completed, not really an error...
          break
        end
      end
      # Give Ruby time to clean up the other thread
      sleep 1

      if thread.alive?
        # We need to kill the process, because killing the thread leaves
        # the process alive but detached, annoyingly enough.
        Process.kill("TERM", pid)
      end
    ensure
      stdin.close if stdin
      stdout.close if stdout
      stderr.close if stderr
    end
    return out.force_encoding("UTF-8"), err.force_encoding("UTF-8"), thread.value
  end

  def run_script(commands, env={})
    allout = ""
    allerr = "" 
    allresult = 0

    commands.each { |cmd|
      if @config.os == "Windows"
        $logger.warn "Unable to set timeout for process execution on windows"
        stdout, stderr, result = Open3::capture3(env, cmd)
      else
        # allow up to 6 hours
        stdout, stderr, result = run_with_timeout(env, cmd, 60*60*6)
      end

      stdout.split("\n").each { |l| 
        $logger.debug("cmd: #{cmd}: stdout: #{l}")
      }

      stderr.split("\n").each { |l| 
        $logger.info("cmd: #{cmd}: stderr: #{l}")
      }

      if cmd != commands.last && result != 0
        $logger.error("Error running script command: #{stderr}")
        raise stderr
      end

      allout += stdout
      allerr += stderr

      if result && result.exitstatus
        allresult += result.exitstatus
      else
        # any old failure result will do
        allresult = 1 
      end
    }

    return allout, allerr, allresult
  end

  def device_tag compiler
    build_type_tag = ""
    if !compiler[:build_tag].nil?
      build_type_tag = "-#{compiler[:build_tag]}"
    end

    if compiler[:build_type] !~ /release/i
      build_type_tag = "#{build_type_tag}-#{compiler[:build_type]}"
    end
   
    return build_type_tag
  end

  def device_id compiler
    "#{compiler[:architecture_description]}-#{@config.os}-#{@config.os_release}-#{compiler[:description]}#{ device_tag(compiler) }"
  end

  def build_base_name compiler
    "#{@config.repository_name}-#{@buildid}-#{device_id(compiler)}"
  end

  def results_file_name compiler
    "#{build_base_name compiler}-results.html"
  end

  def short_build_base_name compiler
    "#{@config.repository_name}-#{compiler[:architecture_description]}-#{@config.os}-#{@buildid}"
  end

  def needs_release_package compiler

    if compiler[:analyze_only]
      return false
    else
      return true
    end

  end


  def checkout(src_dir)
    # TODO update this to be a merge, not just a checkout of the pull request branch
    FileUtils.mkdir_p src_dir

    if @config.pull_id.nil?
      out, err, result = run_script(
        ["cd #{src_dir} && git init",
         "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} #{@refspec}" ])

      if !@commit_sha.nil? && @commit_sha != "" && result == 0
        out, err, result = run_script( ["cd #{src_dir} && git checkout #{@commit_sha}"] );
      end
    else 
      out, err, result = run_script(
        ["cd #{src_dir} && git init",
         "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} refs/pull/#{@config.pull_id}/head",
         "cd #{src_dir} && git checkout FETCH_HEAD" ])
    end

    return result == 0

  end


  def configuration
    return @config
  end


  def do_package(compiler, regression_baseline)
    $logger.info("Beginning packaging phase #{is_release} #{needs_release_package(compiler)}")


    if (ENV["DECENT_CI_ALL_RELEASE"] || (is_release && needs_release_package(compiler))) && !compiler[:skip_packaging]
      src_dir = get_src_dir compiler
      build_dir = get_build_dir compiler

      @created_dirs << src_dir
      @created_dirs << build_dir

      if compiler[:release_build_enable_pgo]
        $logger.info("Release build PGO enabled, starting training build")
        build_succeeded = do_build compiler, regression_baseline, {:training => true, :release=>false}
        $logger.info("Release build PGO enabled, starting training tests")
        do_test compiler, regression_baseline, {:training => true}
        $logger.info("Release build PGO enabled, starting final build")
        build_succeeded = do_build compiler, regression_baseline, {:training => false, :release => true}
      else
        build_succeeded = do_build compiler, regression_baseline, {:training => false, :release => true}
      end

      start_time = Time.now
      case @config.engine
      when "cmake"
        begin
          @package_location = cmake_package compiler, src_dir, build_dir, compiler[:build_type]
        rescue => e
          $logger.error("Error creating package #{e}")
          @package_time = Time.now - start_time
          raise
        end
      else
        @package_time = Time.now - start_time
        raise "Unknown Build Engine"
      end

      @package_time = Time.now - start_time
    end
  end


  def needs_run compiler
    return true if @test_run

    file_names = []
    begin 
      files = github_query(@client) { @client.content @config.results_repository, :path=>@config.results_path }

      files.each { |f|
        file_names << f.name
      }
    rescue Octokit::NotFound => e
      # repository doesn't have a _posts folder yet
    end

    file_names.each{ |f|
      return false if f.end_with? results_file_name(compiler)
    }

    return true
  end

  def get_initials(str)
    # extracts just the initials from the string
    str.gsub(/[_\-]./){ |s| s[1].upcase }.sub(/./){|s| s.upcase}.gsub(/[a-z]/, '')
  end

  def get_short_form(str)
    if ((str =~ /.*[A-Z].*/ && str =~ /.*[a-z].*/) || str =~ /.*_.*/ || str =~ /.*-.*/)
      return get_initials(str)
    else
      return str
    end
  end

  def get_src_dir(compiler)
    "#{get_short_form(@config.repository_name)}-#{@short_buildid}-#{compiler[:architecture_description]}-#{get_short_form(compiler[:description])}#{ get_short_form(device_tag(compiler)) }"
  end

  def get_build_dir(compiler)
    "#{get_src_dir compiler}/build"
  end

  def get_regression_dir(compiler)
    "#{get_src_dir compiler}/regressions"
  end


  def do_build(compiler, regression_baseline, flags={:training => false, :release => false} )
    src_dir = get_src_dir compiler
    build_dir = get_build_dir compiler

    @created_dirs << src_dir
    @created_dirs << build_dir


    checkout_succeeded  = checkout src_dir

    if compiler[:name] == "cppcheck"
      start_time = Time.now
      cppcheck compiler, src_dir, build_dir
      @build_time = 0 if @build_time.nil?
      # handle the case where build is called more than once
      @build_time = @build_time + (Time.now - start_time)
    else
      case @config.engine
      when "cmake"
        start_time = Time.now
        build_succeeded = cmake_build compiler, src_dir, build_dir, compiler[:build_type], get_regression_dir(compiler), regression_baseline, flags if checkout_succeeded
        @build_time = 0 if @build_time.nil?
        # handle the case where build is called more than once
        @build_time = @build_time + (Time.now - start_time)
      else
        raise "Unknown Build Engine"
      end
    end
  end

  def do_test(compiler, regression_baseline, flags={:training => false} )
    src_dir = get_src_dir compiler
    build_dir = get_build_dir compiler

    @created_dirs << src_dir
    @created_dirs << build_dir

    build_succeeded = do_build compiler, regression_baseline

    if compiler[:name] == "cppcheck"
    else
      case @config.engine
      when "cmake"
        start_time = Time.now
        if !ENV["DECENT_CI_SKIP_TEST"]
          cmake_test compiler, src_dir, build_dir, compiler[:build_type], flags if build_succeeded 
        else
          $logger.debug("Skipping test, DECENT_CI_SKIP_TEST is set in the environment")
        end
        @test_time = 0 if @test_time.nil?
        # handle the case where test is called more than once
        @test_time = @test_time + (Time.now - start_time)
      else
        raise "Unknown Build Engine"
      end
    end
  end

  def needs_regression_test(compiler)
    if (!@config.regression_script.nil? || !@config.regression_repository.nil?) && !compiler[:analyze_only] && !ENV["DECENT_CI_SKIP_REGRESSIONS"]
      return true
    else
      return false
    end
  end

  def clone_regression_repository compiler
    regression_dir = get_regression_dir compiler
    @created_regression_dirs << regression_dir
    FileUtils.mkdir_p regression_dir



    if !@config.regression_repository.nil?
      out, err, result = run_script(
        ["cd #{regression_dir} && git init",
         "cd #{regression_dir} && git pull https://#{@config.token}@github.com/#{@config.regression_repository}" ])

      if !@config.regression_commit_sha.nil? && @config.regression_commit_sha != "" && result == 0
        out, err, result = run_script( ["cd #{regression_dir} && git checkout #{@config.regression_commit_sha}"] )
      elsif !@config.regression_branch.nil? && @config.regression_branch != "" && result == 0
        out, err, result = run_script( ["cd #{regression_dir} && git checkout #{@config.regression_branch}"] )
      end

    end
  end

  def do_regression_test(compiler, base)
    regression_dir = get_regression_dir compiler

    build_dir_1 = File.expand_path(base.get_build_dir compiler)
    build_dir_2 = File.expand_path(get_build_dir compiler)
    src_dir_1 = File.expand_path(base.get_src_dir compiler)
    src_dir_2 = File.expand_path(get_src_dir compiler)

    script = []
    script << @config.regression_script
    script.flatten!

    script.map! { |line|
      line = "cd #{regression_dir} && #{line}"
    }


    $logger.debug("Running regression script: " + script.to_s)

    if !script.empty?
      start_time = Time.now

      out,err,result = run_script(script, {"REGRESSION_NUM_PROCESSES"=>compiler[:num_parallel_builds].to_s, "REGRESSION_BASE"=>build_dir_1, "REGRESSION_MOD"=>build_dir_2, "REGRESSION_BASE_SRC"=>src_dir_1, "REGRESSION_MOD_SRC"=>src_dir_2})

      results = process_regression_results out,err,result
      if @test_results.nil?
        @test_results = results
      else
        @test_results = @test_results + results
      end

      time = Time.now - start_time
      if @test_time.nil?
        @test_time = time
      else
        @test_time += time
      end

      return result == 0
    else
      return true
    end
  end

  def unhandled_failure e
    @failure = e
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

  def clean_up compiler
    if !@test_run
      @created_dirs.each { |d|
        begin 
          FileUtils.rm_rf(d)
        rescue => e
          $logger.error("Error cleaning up directory #{e}")
        end
      }
    end
  end

  def clean_up_regressions compiler
    if !@test_run
      @created_regression_dirs.each { |d|
        begin 
          FileUtils.rm_rf(d)
        rescue => e
          $logger.error("Error cleaning up directory #{e}")
        end
      }
    end
  end

  def next_build
    @created_dirs = []
    @created_regression_dirs = []
    @package_location = nil
    @test_results = nil
    @build_results = SortedSet.new()
    @package_results = SortedSet.new()
    @dateprefix = nil
    @failure = nil
    @build_time = nil
    @test_time = nil
    @package_time = nil
    @install_time = nil
  end

  def post_results compiler, pending
    if @dateprefix.nil?
      @dateprefix = DateTime.now.utc.strftime("%F")
    end

    if !@test_run
      if !@package_location.nil? && @config.post_release_package
        $logger.info("Uploading package #{@package_location}")

        num_tries = 3
        try_num = 0
        succeeded = false

        fatal_failure = false

        asset_name = Pathname.new(@package_location).basename.to_s
        while try_num < num_tries && !succeeded && !fatal_failure
          response = nil

          begin 
            response = github_query(@client) { @client.upload_asset(@release_url, @package_location, :content_type=>compiler[:package_mimetype], :name=>asset_name) }
          rescue => e
            if try_num == 0 && e.to_s.include?("already_exists")
              $logger.error("already_exists error on 0th attempt, fatal, we shall not overwrite existing upload");
              @package_results << CodeMessage.new("CMakeLists.txt", 1, 0, "error", "Error, asset already_exists on 0th try, refusing to upload asset: #{e.to_s}")
              fatal_failure = true
              try_num = try_num + 1
              next
            else
              $logger.error("Error uploading asset, trying again: #{e.to_s}");
              @package_results << CodeMessage.new("CMakeLists.txt", 1, 0, "warning", "Error while attempting to upload release asset.\nDuring attempt #{try_num}\n#{e.to_s}")
            end
          end

          if response && response.state != "new"
            $logger.info("Asset upload appears to have succeeded. url: #{response.url}, state: #{response.state}")
            succeeded = true
          else
            $logger.error("Asset upload appears to have failed, going to try and delete the failed bits.")
            asset_url = nil

            if !response.nil? && response.state == "new"
              $logger.error("Error uploading asset #{response.url}");
              asset_url = response.url
            end

            if asset_url.nil?
              $logger.error("nil response, attempting to find release url");
              assets = github_query(@client) { @client.release_assets(@release_url) }

              assets.each { |a|
                if a.name == asset_name
                  asset_url = a.url
                  break
                end
              }

              if !asset_url.nil?
                $logger.error("Found release url in list of assets: #{asset_url}");
              end
            end

            if asset_url
              $logger.error("Deleting existing asset_url and trying again #{asset_url}");
              @package_results << CodeMessage.new("CMakeLists.txt", 1, 0, "warning", "Error while attempting to upload release asset, deleting and trying again. #{asset_url}\nDuring attempt #{try_num}")
              begin 
                response = github_query(@client) { @client.delete_release_asset(asset_url) }
              rescue => e
                $logger.error("Error deleting failed asset, continuing to next try #{e}")
                @package_results << CodeMessage.new("CMakeLists.txt", 1, 0, "warning", "Error while attempting to delete failed release asset upload.\nDuring attempt #{try_num}\nRelease asset #{e.to_s}")
              end
            end
          end

          try_num = try_num + 1
        end

        if !succeeded
          $logger.error("After #{try_num} tries we still failed to upload the release asset.");
          @package_results << CodeMessage.new("CMakeLists.txt", 1, 0, "error", "#{try_num} attempts where made to upload release assets and all failed")
        end

      end
    end

    test_results_data = []

    test_results_passed = 0
    test_results_total = 0

    if !@test_results.nil?
      @test_results.each { |t| 
        test_results_total += 1
        test_results_passed += 1 if t.passed

        test_results_data << t.inspect;
      }
    end

    build_errors = 0
    build_warnings = 0
    build_results_data = []

    if !@build_results.nil?
      @build_results.each { |b|
        build_errors += 1 if b.is_error
        build_results_data << b.inspect
      }
      build_warnings = @build_results.count - build_errors
    end


    package_errors = 0
    package_warnings = 0
    package_results_data = []

    if !@package_results.nil?
      @package_results.each { |b|
        package_errors += 1 if b.is_error
        package_warnings += 1 if b.is_warning

        package_results_data << b.inspect
      }
    end



    json_data = {"build_results"=>build_results_data, "test_results"=>test_results_data, "failure" => @failure, "package_results"=>package_results_data}

    json_document = 
<<-eos
---
title: #{build_base_name compiler}
permalink: #{build_base_name compiler}.html
tags: data
layout: ci_results
date: #{DateTime.now.utc.strftime("%F %T")}
unhandled_failure: #{!@failure.nil?}
build_error_count: #{build_errors}
build_warning_count: #{build_warnings}
package_error_count: #{package_errors}
package_warning_count: #{package_warnings}
test_count: #{test_results_total}
test_passed_count: #{test_results_passed}
repository: #{@repository}
compiler: #{compiler[:name]}
compiler_version: #{compiler[:version]}
architecture: #{compiler[:architecture]}
os: #{@config.os}
os_release: #{@config.os_release}
is_release: #{is_release}
release_packaged: #{!@package_location.nil?}
packaging_skipped: #{compiler[:skip_packaging]}
package_name: #{@package_location.nil? ? nil : Pathname.new(@package_location).basename}
tag_name: #{@tag_name}
commit_sha: #{@commit_sha}
branch_name: #{@branch_name}
test_run: #{!@test_results.nil?}
pull_request_issue_id: "#{pull_request_issue_id}"
pull_request_base_repository: #{@pull_request_base_repository}
pull_request_base_ref: #{@pull_request_base_ref}
device_id: #{device_id compiler}
pending: #{pending}
analyze_only: #{compiler[:analyze_only]}
build_time: #{@build_time}
test_time: #{@test_time}
package_time: #{@package_time}
install_time: #{@install_time}
results_repository: #{@config.results_repository}
machine_name: #{Socket.gethostname}
machine_ip: #{Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address}
---

#{JSON.pretty_generate(json_data)}

eos

    test_failed = false
    if @test_results.nil?
      test_color = "red"
      test_failed = true
      test_string = "NA"
    else
      if test_results_total == 0
        test_percent = 100.0
      else 
        test_percent = (test_results_passed.to_f / test_results_total.to_f) * 100.0
      end

      if test_percent > 99.99
        test_color = "green"
      elsif test_percent > 90.0
        test_color = "yellow"
      else
        test_color = "red"
        test_failed = true
      end
      test_string = "#{test_percent}%25"
    end

    test_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Test Badge](http://img.shields.io/badge/tests%20passed-#{test_string}-#{test_color}.svg)</a>"

    if compiler[:analyze_only] 
      test_failed = false
      test_badge = ""
    end



    build_failed = false
    if build_errors > 0
      build_color = "red"
      build_string = "failing"
      build_failed = true
    elsif build_warnings > 0
      build_color = "yellow"
      build_string = "warnings"
    else
      build_color = "green"
      build_string = "passing"
    end

    build_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Build Badge](http://img.shields.io/badge/build%20status-#{build_string}-#{build_color}.svg)</a>"

    failed = build_failed || test_failed || !@failure.nil?
    github_status = pending ? "pending" : (failed ? "failure" : "success")

    if pending 
      github_status_message = "Build Pending"
    else
      if build_failed
        github_status_message = "Build Failed"
      elsif test_failed
        github_status_message = "Tests Failed"
      else
        github_status_message = "OK (#{test_results_passed} of #{test_results_total} tests passed)"
      end
    end

    if !@failure.nil?    
      github_document = 
<<-eos
<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>Unhandled Fundamental Failure</a>
eos
    else
      github_document = 
<<-eos
#{@refspec} (#{@author}) - #{device_id compiler}: #{github_status_message}

#{build_badge} #{test_badge}
eos
    end

    if !@test_run
      begin
        if pending
          $logger.info("Posting pending results file");
          response =  github_query(@client) { @client.create_contents(@config.results_repository,
                                             "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
                                             "Commit initial build results file: #{@dateprefix}-#{results_file_name compiler}", 
                                             json_document) }

          $logger.debug("Results document sha set: #{response.content.sha}")

          @results_document_sha = response.content.sha

        else
          if @results_document_sha.nil?
            raise "Error, no prior results document sha set"
          end

          $logger.info("Updating contents with sha #{@results_document_sha}")
          response =  github_query(@client) { @client.update_contents(@config.results_repository,
                                             "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
                                             "Commit final build results file: #{@dateprefix}-#{results_file_name compiler}",
                                             @results_document_sha,
                                             json_document) }
        end
      rescue => e
        $logger.error "Error creating / updating results contents file: #{e}"
        raise e
      end

      if !pending && @config.post_results_comment
        if !@commit_sha.nil? && @repository == @config.repository
          response = github_query(@client) { @client.create_commit_comment(@config.repository, @commit_sha, github_document) }
        elsif !pull_request_issue_id.nil?
          response = github_query(@client) { @client.add_comment(@config.repository, pull_request_issue_id, github_document) }
        end
      end

      if !@commit_sha.nil? && @config.post_results_status
        if !@pull_request_base_repository.nil?
          response = github_query(@client) { @client.create_status(@pull_request_base_repository, @commit_sha, github_status, :context=>device_id(compiler), :target_url=>"#{@config.results_base_url}/#{build_base_name compiler}.html", :description=>github_status_message) }
        else
          response = github_query(@client) { @client.create_status(@config.repository, @commit_sha, github_status, :context=>device_id(compiler), :target_url=>"#{@config.results_base_url}/#{build_base_name compiler}.html", :description=>github_status_message) }
        end
      end

    else 
      File.open("#{@dateprefix}-#{results_file_name compiler}", "w+") { |f| f.write(json_document) }
      File.open("#{@dateprefix}-COMMENT-#{results_file_name compiler}", "w+") { |f| f.write(github_document) }
    end


  end

end


