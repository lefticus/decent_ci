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
require_relative 'cmake.rb'
require_relative 'configuration.rb'
require_relative 'resultsprocessor.rb'
require_relative 'cppcheck.rb'


## Contains the logic flow for executing builds and parsing results
class PotentialBuild
  include CMake
  include Configuration
  include ResultsProcessor
  include Cppcheck

  def initialize(client, token, repository, tag_name, commit_sha, branch_name, release_url, release_assets, 
                 pull_id, pull_request_base_repository, pull_request_base_ref)
    @logger = Logger.new(STDOUT)
    @client = client
    @config = load_configuration(repository, (tag_name.nil? ? commit_sha : tag_name))
    @config.repository_name = @client.repo(repository).name
    @config.repository = repository
    @config.token = token
    @repository = repository
    @tag_name = tag_name
    @commit_sha = commit_sha
    @branch_name = branch_name
    @release_url = release_url
    @release_assets = release_assets

    @buildid = @tag_name ? @tag_name : @commit_sha
    @refspec = @tag_name ? @tag_name : @branch_name

    @pull_id = pull_id
    @pull_request_base_repository = pull_request_base_repository
    @pull_request_base_ref = pull_request_base_ref


    @buildid = "#{@buildid}-PR#{@pull_id}" if !@pull_id.nil?

    @created_dirs = []
    @package_location = nil
    @test_results = nil
    @build_results = SortedSet.new()
    @package_results = SortedSet.new()
    @dateprefix = nil
    @failure = nil
    @test_run = false
    @build_time = nil
    @test_time = nil
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
        @logger.warn "Unable to set timeout for process execution on windows"
        stdout, stderr, result = Open3::capture3(env, cmd)
      else
        stdout, stderr, result = run_with_timeout(env, cmd)
      end

      stdout.split("\n").each { |l| 
        @logger.debug("cmd: #{cmd}: stdout: #{l}")
      }

      stderr.split("\n").each { |l| 
        @logger.info("cmd: #{cmd}: stderr: #{l}")
      }

      if cmd != commands.last && result != 0
        @logger.error("Error running script command: #{stderr}")
        raise stderr
      end

      allout += stdout
      allerr += stderr
      allresult += result.exitstatus
    }

    return allout, allerr, allresult
  end

  def device_id compiler
    "#{compiler[:architecture_description]}-#{@config.os}-#{@config.os_release}-#{compiler[:description]}#{ compiler[:build_type] =~ /release/i ? "" : "-#{compiler[:build_type]}" }"
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


  def package_name compiler
    "#{short_build_base_name(compiler)}"
  end


  def package_full_name compiler
    "#{short_build_base_name compiler}.#{compiler[:package_extension]}"
  end

  def needs_release_package compiler
    if @release_assets.nil?
      return true
    end

    @release_assets.each { |f|
      if f.name == package_full_name(compiler)
        return false
      end
    }
    return true
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


  def do_package compiler
    @logger.info("Beginning packaging phase #{is_release} #{needs_release_package(compiler)}")

    if is_release # && needs_release_package(compiler)
      src_dir = "#{build_base_name compiler}-release"
      build_dir = "#{src_dir}/build"

      @created_dirs << src_dir
      @created_dirs << build_dir

      checkout src_dir

      start_time = Time.now
      case @config.engine
      when "cmake"
        cmake_build compiler, src_dir, build_dir, compiler[:build_type]
      else
        raise "Unknown Build Engine"
      end

      begin 
        @package_location = cmake_package compiler, src_dir, build_dir, compiler[:build_type]
      rescue => e
        @logger.error("Error creating package #{e}")
      end
      end_time = Time.now
      @package_time = end_time - start_time

    end
  end

  def parse_error_messages compiler, src_dir, build_dir, output
    results = []
    output.split("\n").each{ |l|
      msg = parse_gcc_line(compiler, src_dir, build_dir, l)
      msg = parse_msvc_line(compiler, src_dir, build_dir, l) if msg.nil?
      msg = parse_generic_line(compiler, src_dir, build_dir, l) if msg.nil?

      results << msg if !msg.nil?
    }

    return results
  end


  def needs_run compiler
    return true if @test_run

    file_names = []
    begin 
      files = @client.content @config.results_repository, :path=>@config.results_path

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

  def do_test(compiler)
    src_dir = build_base_name compiler
    build_dir = "#{build_base_name compiler}/build"

    @created_dirs << src_dir
    @created_dirs << build_dir

    checkout_succeeded  = checkout src_dir

    if compiler[:name] == "cppcheck"
      cppcheck compiler, src_dir, build_dir
    else
      case @config.engine
      when "cmake"
        start_time = Time.now
        build_succeeded = cmake_build compiler, src_dir, build_dir, compiler[:build_type] if checkout_succeeded
        build_time = Time.now
        # build_succeeded = true
        cmake_test compiler, src_dir, build_dir, compiler[:build_type] if build_succeeded 
        end_time = Time.now

        @build_time = build_time - start_time
        @test_time = end_time - build_time
      else
        raise "Unknown Build Engine"
      end
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
          @logger.error("Error cleaning up directory #{e}")
        end
      }
    end
  end

  def next_build
    @created_dirs = []
    @package_location = nil
    @test_results = nil
    @build_results = SortedSet.new()
    @package_results = SortedSet.new()
    @dateprefix = nil
    @failure = nil
    @build_time = nil
    @test_time = nil
    @package_time = nil
  end

  def post_results compiler, pending
    if @dateprefix.nil?
      @dateprefix = DateTime.now.utc.strftime("%F")
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
#{device_id compiler}: #{(failed) ? "Failed" : "Succeeded"}

#{build_badge} #{test_badge}
eos
    end

    if !@test_run
      begin
        if pending
          @logger.info("Posting pending results file");
          response = @client.create_contents(@config.results_repository,
                                             "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
          "Commit initial build results file: #{@dateprefix}-#{results_file_name compiler}",
          json_document)
          @logger.debug("Results document sha set: #{response.content.sha}")

          @results_document_sha = response.content.sha

        else
          if @results_document_sha.nil?
            raise "Error, no prior results document sha set"
          end

          @logger.info("Updating contents with sha #{@results_document_sha}")
          response = @client.update_contents(@config.results_repository,
                                             "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
          "Commit final build results file: #{@dateprefix}-#{results_file_name compiler}",
          @results_document_sha,
            json_document)
        end
      rescue => e
        @logger.error "Error creating / updating results contents file: #{e}"
        raise e
      end

      if !pending && @config.post_results_comment
        if !@commit_sha.nil? && @repository == @config.repository
          response = @client.create_commit_comment(@config.repository, @commit_sha, github_document)
        elsif !pull_request_issue_id.nil?
          response = @client.add_comment(@config.repository, pull_request_issue_id, github_document);
        end
      end

      if !@commit_sha.nil? && @config.post_results_status
        response = @client.create_status(@config.repository, @commit_sha, github_status, :context=>device_id(compiler), :target_url=>"#{@config.results_base_url}/#{build_base_name compiler}.html", :description=>github_status_message, :accept => Octokit::Client::Statuses::COMBINED_STATUS_MEDIA_TYPE)
      end

      if !@package_location.nil? && @config.post_release_package
        @client.upload_asset(@release_url, @package_location, :content_type=>compiler[:package_mimetype], :name=>Pathname.new(@package_location).basename.to_s)
      end
    else 
      File.open("#{@dateprefix}-#{results_file_name compiler}", "w+") { |f| f.write(json_document) }
      File.open("#{@dateprefix}-COMMENT-#{results_file_name compiler}", "w+") { |f| f.write(github_document) }
    end


  end

end


