require 'octokit'
require 'json'
require 'open3'
require 'pathname'
require 'active_support/core_ext/hash'
require 'find'
require 'logger'
require 'fileutils'
require 'ostruct'

class CodeMessage
  def initialize(filename, linenumber, colnumber, messagetype, message)
    @filename = filename
    @linenumber = linenumber
    @colnumber = colnumber
    @messagetype = messagetype
    @message = message
  end

  def is_warning
    @messagetype =~ /.*warn.*/i
  end

  def is_error
    @messagetype =~ /.*err.*/i
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

end

class TestResult
  def initialize(name, status, time)
    @name = name
    @status = status
    @time = time
  end

  def passed
    return @status == "passed"
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

end

class PotentialBuild

  def initialize(client, config, repository, tag_name, commit_sha, branch_name, release_url, release_assets, 
                 pull_id, pull_request_base_repository, pull_request_base_ref)
    @config = config
    @repository = repository
    @tag_name = tag_name
    @commit_sha = commit_sha
    @branch_name = branch_name
    @release_url = release_url
    @release_assets = release_assets
    @needs_run = true
    @client = client

    @buildid = @tag_name ? @tag_name : @commit_sha
    @refspec = @tag_name ? @tag_name : @branch_name

    @pull_id = pull_id
    @pull_request_base_repository = pull_request_base_repository
    @pull_request_base_ref = pull_request_base_ref


    @buildid = "#{@buildid}-PR#{@pull_id}" if !@pull_id.nil?

    @created_dirs = []
    @logger = Logger.new(STDOUT)
    @package_location = nil
    @test_results = nil
    @build_results = nil
    @dateprefix = nil

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

  def runScript(commands)
    allout = ""
    allerr = "" 
    allresult = 0

    commands.each { |cmd|
      stdout, stderr, result = Open3.capture3(cmd)

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
    "#{compiler[:architecture_description]}-#{@config.os}-#{@config.os_release}-#{compiler[:description]}"
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



  def relative_path(p, compiler)
    return Pathname.new(p).realpath.relative_path_from(Pathname.new(build_base_name compiler).realdirpath)
  end


  def process_msvc_results(compiler, stdout, stderr, result, builddir)
    results = []
    stdout.split("\n").each{ |err|
      /\s+(?<filename>\S+)\((?<linenumber>[0-9]+)\): (?<messagetype>\S+) (?<messagecode>\S+): (?<message>.*) \[.*\]/ =~ err

      if !filename.nil? && !messagetype.nil? && messagetype != "info"
        results << CodeMessage.new(relative_path(builddir + "/" + filename, compiler), linenumber, 0, messagetype, message)
      end
    }

    @build_results = results
    return result
  end


  def process_gcc_results(compiler, stdout, stderr, result)
    results = []

    stderr.split("\n").each { |err|
      /(?<filename>\S+):(?<linenumber>[0-9]+):(?<colnumber>[0-9]+): (?<messagetype>\S+): (?<message>.*)/ =~ err

      if !filename.nil? && !messagetype.nil? && messagetype != "info"
        results << CodeMessage.new(relative_path(filename, compiler), linenumber, colnumber, messagetype, message)
      end
    }

    @build_results = results

    return result == 0
  end

  def checkout(src_dir)
    # TODO update this to be a merge, not just a checkout of the pull request branch
    FileUtils.mkdir_p src_dir
    out, err, result = runScript(
      ["cd #{src_dir} && git init",
       "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} #{@refspec}" ])

    if !@commit_sha.nil? && @commit_sha != "" && result == 0
      out, err, result = runScript( ["cd #{src_dir} && git checkout #{@commit_sha}"] );
    end

    return result == 0

  end

  def cmake_build(compiler, src_dir, build_dir, build_type)
    FileUtils.mkdir_p build_dir


    out, err, result = runScript(
      ["cd #{build_dir} && cmake ../ -DCPACK_PACKAGE_FILE_NAME:STRING=#{package_name compiler} -DCMAKE_BUILD_TYPE:STRING=#{build_type} -G \"#{compiler[:build_generator]}\""])


    if compiler[:name] =~ /visual studio/i
      solution_path = nil

      Find.find(build_dir) do |path|
        if path =~ /.*\.sln/i
          solution_path = path
          break
        end
      end

      if solution_path.nil?
        raise "generated solution file not found"
      end

      solution_path = Pathname.new(solution_path).relative_path_from(Pathname.new(build_dir))

      out, err, result = runScript(
        ["cd #{build_dir} && \"#{compiler[:build_tool]}\" #{solution_path} /p:Configuration=#{build_type}"])

      return process_msvc_results(compiler, out,err,result,build_dir)
    else
      out, err, result = runScript(
        ["cd #{build_dir} && \"#{compiler[:build_tool]}\""])

      return process_gcc_results(compiler, out,err,result)
    end
  end

  def cmake_package(compiler, build_dir, build_type)
    pack_stdout, pack_stderr, pack_result = runScript(
      ["cd #{build_dir} && cpack -G #{build_package_generator} -C #{build_type}"])

    if pack_result != 0
      raise "Error building package: #{pack_stderr}"
    end

    return "#{build_dir}/#{package_full_name compiler}"
  end

  def do_package compiler
    if is_release && @needs_run && needs_release_package(compiler)
      src_dir = "#{build_base_name compiler}-release"
      build_dir = "#{src_dir}/build"

      @created_dirs << src_dir
      @created_dirs << build_dir

      checkout src_dir

      case @config.engine
      when "cmake"
        cmake_build compiler, src_dir, build_dir, "Release"
      else
        raise "Unknown Build Engine"
      end

      begin 
        @package_location = cmake_package compiler, build_dir, "Release"
      rescue => e
        @logger.error("Error creating package #{e}")
      end

    end
  end

  def process_ctest_results build_dir, stdout, stderr, result
    Find.find(build_dir) do |path|
      if path =~ /.*Test.xml/
        results = []

        xml = Hash.from_xml(File.open(path).read)
        testresults = xml["Site"]["Testing"]
        testresults.each { |t, n|
          if t == "Test"
            r = n["Results"]
            if n["Status"] == "notrun"
              results << TestResult.new(n["Name"], n["Status"], 0)
            else
              if r
                nm = r["NamedMeasurement"]

                if !nm.nil?
                  nm.each { |measurement|
                    if measurement["name"] == "Execution Time"
                      results << TestResult.new(n["Name"], n["Status"], measurement["Value"]);
                    end
                  }
                end
              end
            end
          end
        }

        return results
      end

    end
  end

  def filter_build files, compiler
    files.each{ |f|
      @needs_run = false if f.end_with? results_file_name(compiler)
    }
  end

  def cmake_test(compiler, build_dir, build_type)
    test_stdout, test_stderr, test_result = runScript(["cd #{build_dir} && ctest -D ExperimentalTest -C #{build_type}"]);
    @test_results = process_ctest_results build_dir, test_stdout, test_stderr, test_result
  end

  def do_test(compiler)
    if @needs_run
      src_dir = build_base_name compiler
      build_dir = "#{build_base_name compiler}/build"

      @created_dirs << src_dir
      @created_dirs << build_dir

      checkout_succeeded  = checkout src_dir

      case @config.engine
      when "cmake"
        build_succeeded = cmake_build compiler, src_dir, build_dir, "Debug" if checkout_succeeded
        cmake_test compiler, build_dir, "Debug" if build_succeeded 
      else
        raise "Unknown Build Engine"
      end
    end
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

  def clean_up compiler
    @created_dirs.each { |d|
      begin 
        FileUtils.rm_rf(d)
      rescue => e
        @logger.error("Error cleaning up directory #{e}")
      end
    }
  end

  def next_build
    @dateprefix = nil
  end

  def post_results compiler, pending
    if !@needs_run
      return  # nothing to do
    end

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
        build_warnings += 1 if b.is_warning

        build_results_data << b.inspect
      }
    end

    json_data = {"build_results"=>build_results_data, "test_results"=>test_results_data}

    json_document = 
<<-eos
---
title: #{build_base_name compiler}
permalink: #{build_base_name compiler}.html
tags: data
layout: ci_results
date: #{DateTime.now.utc.strftime("%F %T")}
build_error_count: #{build_errors}
build_warning_count: #{build_warnings}
test_count: #{test_results_total}
test_passed_count: #{test_results_passed}
repository: #{@repository}
compiler: #{@config.compiler}
compiler_version: #{@config.compiler_version}
architecture: #{@config.architecture}
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
---

#{json_data.to_json}

eos

    test_failed = false
    if @test_results.nil?
      test_color = "red"
      test_failed = true
      test_string = "NA"
    else
      if test_results_total == 0
        test_percent == 100.0
      else 
        test_percent = (test_results_passed / test_results_total) * 100.0
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

    failed = build_failed || test_failed
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
    

    github_document = 
<<-eos
#{device_id compiler}: #{(failed) ? "Failed" : "Succeeded"}

#{build_badge} #{test_badge}
eos

    begin
      if pending
        response = @client.create_contents(@config.results_repository,
                                           "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
                                           "Commit initial build results file: #{@dateprefix}-#{results_file_name compiler}",
                                           json_document)
        @logger.info("Results document sha set: #{response.content.sha}")

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

    if !pending
      if !@commit_sha.nil? && @repository == @config.repository
        response = @client.create_commit_comment(@config.repository, @commit_sha, github_document)
      elsif !pull_request_issue_id.nil?
        response = @client.add_comment(@config.repository, pull_request_issue_id, github_document);
      end
    end

    if !@commit_sha.nil?
      response = @client.create_status(@config.repository, @commit_sha, github_status, :context=>device_id(compiler), :target_url=>"#{@config.results_base_url}/#{build_base_name compiler}.html", :description=>github_status_message, :accept => Octokit::Client::Statuses::COMBINED_STATUS_MEDIA_TYPE)
    end


    if !@package_location.nil?
      @client.upload_asset(@release_url, @package_location, :content_type=>compiler[:package_mimetype], :name=>Pathname.new(@package_location).basename.to_s)
    end
  end

end

class Build
  def initialize(config)
    @config = config
    @client = Octokit::Client.new(:access_token=>config.token)
    @user = @client.user
    @user.login
    @potential_builds = []

    @config.repository_name = @client.repo(@config.repository).name
  end

  def query_releases
    releases = @client.releases(@config.repository)

    releases.each { |r| 
      @potential_builds << PotentialBuild.new(@client, @config, @config.repository, r.tag_name, nil, nil, r.url, r.assets, nil, nil, nil)
    }
  end

  def query_branches
    branches = @client.branches(@config.repository)

    branches.each { |b| 
      @potential_builds << PotentialBuild.new(@client, @config, @config.repository, nil, b.commit.sha, b.name, nil, nil, nil, nil, nil)
    }
  end

  def query_pull_requests
    pull_requests = @client.pull_requests(@config.repository, :state=>"open")

    pull_requests.each { |p| 
      @potential_builds << PotentialBuild.new(@client, @config, p.head.repo.full_name, nil, p.head.sha, p.head.ref, nil, nil, p.number, p.base.repo.full_name, p.base.ref)
    }
  end

  def filter_potential_builds compiler

    begin
      files = @client.content @config.results_repository, :path=>@config.results_path

      file_names = []
      files.each { |f|
        file_names << f.name
      }

      @potential_builds.each { |p|
        p.filter_build file_names, compiler
      }
    rescue => e
      # there was an error getting the file list, no big deal (I think), _posts might not exist yet
    end

  end

  def potential_builds
    @potential_builds
  end
end

if RUBY_PLATFORM  =~ /darwin/i
  os_version = "MacOS"
  ver_string = `uname -v`.strip

  /.* Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\.(?<ver_patch>[0-9]+).*:.*/ =~ ver_string
  # the darwin version number - 4 = the point release of macosx
  os_release = "10.#{ver_major - 4}"

elsif RUBY_PLATFORM =~ /linux/i
  os_version = "Linux"
  os_release = "#{`lsb_release -is`.strip}-#{`lsb_release -rs`.strip}"
else
  os_version = "Windows"
  ver_string = `cmd /c ver`.strip

  /.* \[Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\..*\]/ =~ ver_string

  os_release = nil

  case ver_major
  when 5
    case ver_minor
    when 0
      os_release = "2000"
    when 1
      os_release = "XP"
    when 2
      os_release = "2003"
    end
  when 6
    case ver_minor
    when 0
      os_release = "Vista"
    when 1
      os_release = "7"
    when 2
      os_release = "8"
    when 3
      os_release = "8.1"
    end
  end


  if os_release.nil?
    os_release = "Unknown-#{ver_major}.#{ver_minor}"
  end

end


configuration = OpenStruct.new({
  :results_repository => "ChaiScript/chaiscript-build-results",
  :results_path => "_posts",
  :results_base_url => "https://chaiscript.github.io/chaiscript-build-results/",
  :repository => "lefticus/cpp_project_with_errors",
#  :compilers => [{:name => "Visual Studio", :version => "12", :architecture => ""}, {:name => "Visual Studio", :version => "12", :architecture => "Win64"} ],
  :compilers => [{:name => "gcc", :version => "4.8", :architecture => ""} ],
  :os => os_version,
  :os_release => os_release,
  :engine => "cmake",
  :token => ARGV[0]
})

puts ARGV
puts "Token in use: #{configuration.token}"

# go through the list of compilers specified and fill in reasonable defaults
# if there are not any specified already
#
configuration.compilers.each { |compiler|

  if compiler[:architecture].nil? || compiler[:architecture] == ""
    compiler[:architecture_description] = RbConfig::CONFIG["host_cpu"]
  else
    compiler[:architecture_description] = compiler[:architecture]
  end

  description = compiler[:name].gsub(/\s+/, "")

  if !compiler[:version].nil? && compiler[:version] != ""
    description = "#{description}-#{compiler[:version]}"
  end

  compiler[:description] = description

  if compiler[:build_tool].nil? || compiler[:build_tool] == ""
    if compiler[:name] == "Visual Studio"
      compiler[:build_tool] = "c:\\Program Files (x86)\\MSBuild\\12.0\\Bin\\MSBuild.exe"
    else 
      compiler[:build_tool] = "make"
    end
  end

  if compiler[:build_package_generator].nil? || compiler[:build_package_generator] == ""
    case configuration.os
    when "Windows"
      compiler[:build_package_generator] = "NSIS"
    when "Linux"
      if configuration.os_release =~ /.*ubuntu.*/i || configuration.os_release =~ /.*deb.*/i || configuration.os_release =~ /.*mint.*/i
        compiler[:build_package_generator] = "DEB"
      else
        compiler[:build_package_generator] = "RPM"
      end
    when "MacOS"
      compiler[:build_package_generator] = "PackageMaker"
    end
  end

  if compiler[:build_generator].nil? || compiler[:build_generator] == ""
    case compiler[:name]
    when /.*Visual Studio.*/i
      generator = "Visual Studio #{compiler[:version]}"
      if compiler[:architecture] =~ /.*64.*/
        generator = "#{generator} Win64"
      end
      compiler[:build_generator] = generator
    else
      compiler[:build_generator] = "Unix Makefiles"
    end
  end

  if compiler[:package_extension].nil? || compiler[:package_extension] == ""
    case compiler[:build_package_generator]
    when /.*NSIS.*/
      compiler[:package_extension] = "exe"
    when /.*PackageMaker.*/
      compiler[:package_extension] = "dmg"
    when /T.*/
      /T(?<tar_type>[0-9]+)/ =~ compiler[:build_package_generator]
      compiler[:package_extension] = "tar.#{tar_type.downcase}"
    else
      compiler[:package_extension] = compiler[:build_package_generator].downcase
    end
  end

  case compiler[:package_extension]
  when "deb"
    compiler[:package_mimetype] = "application/x-deb"
  else
    compiler[:package_mimetype] = "application/octet-stream"
  end

}



b = Build.new(configuration);

b.query_releases
b.query_branches
b.query_pull_requests

configuration.compilers.each { |compiler|
  b.filter_potential_builds compiler

  b.potential_builds.each { |p|
    p.next_build
    p.post_results compiler, true
    p.do_package compiler
    p.do_test compiler
    p.post_results compiler, false
    p.clean_up compiler
  }
}

