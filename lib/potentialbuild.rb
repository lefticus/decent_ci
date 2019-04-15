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
require 'socket'

require_relative 'codemessage.rb'
require_relative 'testresult.rb'
require_relative 'cmake.rb'
require_relative 'configuration.rb'
require_relative 'resultsprocessor.rb'
require_relative 'cppcheck.rb'
require_relative 'custom_check.rb'
require_relative 'github.rb'
require_relative 'lcov.rb'
require_relative 'runners.rb'

## Contains the logic flow for executing builds and parsing results
class PotentialBuild
  include CMake
  include Configuration
  include ResultsProcessor
  include Cppcheck
  include Lcov
  include CustomCheck
  include Runners

  attr_reader :tag_name
  attr_reader :commit_sha
  attr_reader :branch_name
  attr_reader :repository

  def initialize(client, token, repository, tag_name, commit_sha, branch_name, author, release_url, release_assets, # rubocop:disable Metrics/ParameterLists
                 pull_id, pr_base_repository, pr_base_ref)
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

    @buildid = @tag_name || @commit_sha
    @refspec = @tag_name || @branch_name

    @pull_id = pull_id
    @pull_request_base_repository = pr_base_repository
    @pull_request_base_ref = pr_base_ref

    @short_buildid = get_short_form(@tag_name) || @commit_sha[0..9]
    unless @pull_id.nil?
      @buildid = "#{@buildid}-PR#{@pull_id}"
      @short_buildid = "#{@short_buildid}-PR#{@pull_id}"
    end

    @package_location = nil
    @test_results = nil
    @test_messages = []
    @build_results = SortedSet.new
    @package_results = SortedSet.new
    @dateprefix = nil
    @failure = nil
    @test_run = false
    @build_time = nil
    @test_time = nil
    @install_time = nil
    @package_time = nil
    @coverage_lines = 0
    @coverage_total_lines = 0
    @coverage_functions = 0
    @coverage_total_functions = 0
    @coverage_url = nil
    @asset_url = nil
    @acting_as_baseline = false

    @performance_results = nil
  end

  def set_as_baseline
    @acting_as_baseline = true
  end

  def compilers
    @config.compilers
  end

  def apply_test_run(new_test_run)
    @test_run = new_test_run
  end

  def descriptive_string
    "#{@commit_sha} #{@branch_name} #{@tag_name} #{@buildid}"
  end

  def release?
    !@release_url.nil?
  end

  def pull_request?
    !@pull_id.nil?
  end

  def pull_request_issue_id
    @pull_id
  end

  def running_extra_tests
    $logger.info("Checking if running_extra_tests on branch: #{@branch_name} extra tests branches #{@config.extra_tests_branches}")
    if !@branch_name.nil? && !@config.extra_tests_branches.nil? && @config.extra_tests_branches.count(@branch_name) != 0
      true
    else
      false
    end
  end

  def device_tag(compiler)
    build_type_tag = ''
    build_type_tag = "-#{compiler[:build_tag]}" unless compiler[:build_tag].nil?
    build_type_tag = "#{build_type_tag}-#{compiler[:build_type]}" if compiler[:build_type] !~ /release/i
    build_type_tag
  end

  def device_id(compiler)
    "#{compiler[:architecture_description]}-#{@config.os}-#{@config.os_release}-#{compiler[:description]}#{device_tag(compiler)}"
  end

  def build_base_name(compiler)
    "#{@config.repository_name}-#{@buildid}-#{device_id(compiler)}"
  end

  def results_file_name(compiler)
    "#{build_base_name compiler}-results.html"
  end

  def short_build_base_name(compiler)
    "#{@config.repository_name}-#{compiler[:architecture_description]}-#{@config.os}-#{@buildid}"
  end

  def needs_release_package(compiler)
    if compiler[:analyze_only]
      false
    else
      true
    end
  end

  def checkout(src_dir)
    # TODO: update this to be a merge, not just a checkout of the pull request branch
    FileUtils.mkdir_p src_dir

    if @config.pull_id.nil?
      _, _, result = run_script(
        @config,
        [
          "cd #{src_dir} && git init",
          "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} \"#{@refspec}\""
        ]
      )

      success = !@commit_sha.nil? && @commit_sha != '' && result.zero?
      _, _, result = run_script(@config, ["cd #{src_dir} && git checkout #{@commit_sha}"]) if success
    else
      _, _, result = run_script(
        @config,
        [
          "cd #{src_dir} && git init",
          "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} refs/pull/#{@config.pull_id}/head",
          "cd #{src_dir} && git checkout FETCH_HEAD"
        ]
      )
    end

    result.zero?
  end

  def configuration
    @config
  end

  def needs_coverage(compiler)
    compiler[:coverage_enabled]
  end

  def needs_upload(compiler)
    !compiler[:s3_upload].nil?
  end

  def do_coverage(compiler)
    $logger.info("Beginning coverage calculation phase #{release?} #{needs_release_package(compiler)}")

    return unless needs_coverage(compiler)

    build_dir = this_build_dir
    @coverage_total_lines, @coverage_lines, @coverage_total_functions, @coverage_functions = lcov @config, compiler, build_dir
    return if compiler[:coverage_s3_bucket].nil?

    s3_script = File.dirname(File.dirname(__FILE__)) + '/send_to_s3.py'

    out, = run_script(
      @config,
      [
        "#{s3_script} #{compiler[:coverage_s3_bucket]} #{get_full_build_name(compiler)} #{build_dir}/lcov-html coverage"
      ]
    )

    @coverage_url = out
  end

  def do_upload(compiler)
    $logger.info("Beginning upload phase #{release?} #{needs_upload(compiler)}")

    return unless needs_upload(compiler)

    build_dir = this_build_dir

    s3_script = File.dirname(File.dirname(__FILE__)) + '/send_to_s3.py'

    out, = run_script(
      @config,
      [
        "#{s3_script} #{compiler[:s3_upload_bucket]} #{get_full_build_name(compiler)} #{build_dir}/#{compiler[:s3_upload]} assets"
      ]
    )

    @asset_url = out
  end

  def do_package(compiler, regression_baseline)
    return unless (ENV['DECENT_CI_ALL_RELEASE'] || (release? && needs_release_package(compiler))) && !compiler[:skip_packaging]

    $logger.info("Beginning packaging phase #{release?} #{needs_release_package(compiler)}")
    src_dir = this_src_dir
    build_dir = this_build_dir

    do_build compiler, regression_baseline, :release => true

    start_time = Time.now
    case @config.engine
    when 'cmake'
      begin
        @package_location = cmake_package compiler, src_dir, build_dir, compiler[:build_type]
      rescue => e
        $logger.error("Error creating package #{e}")
        @package_time = Time.now - start_time
        raise
      end
    else
      @package_time = Time.now - start_time
      raise 'Unknown Build Engine'
    end

    @package_time = Time.now - start_time
  end

  def needs_run(compiler)
    return true if @test_run

    file_names = []
    begin
      files = github_query(@client) { @client.content @config.results_repository, :path => "#{@config.results_path}/#{this_branch_folder}" }

      files.each do |f|
        file_names << f.name
      end
    rescue Octokit::NotFound # rubocop:disable Lint/HandleExceptions
      # repository doesn't have a _posts folder yet
    end

    file_names.each do |f|
      return false if f.end_with? results_file_name(compiler)
    end

    true
  end

  def get_initials(str)
    # extracts just the initials from the string
    str.gsub(/[^A-Z0-9\.\-a-z_+]/, '').gsub(/[_\-+]./) { |s| s[1].upcase }.sub(/./, &:upcase).gsub(/[^A-Z0-9\.]/, '')
  end

  def add_dashes(str)
    str.gsub(/([0-9]{3,})([A-Z])/, '\1-\2').gsub(/([A-Z])([0-9]{3,})/, '\1-\2')
  end

  def get_short_form(str)
    return nil if str.nil?

    return_value = if str.length <= 10 && str =~ /[a-zA-Z]/
                     str
                   elsif (str =~ /.*[A-Z].*/ && str =~ /.*[a-z].*/) || str =~ /.*_.*/ || str =~ /.*-.*/ || str =~ /.*\+.*/
                     add_dashes(get_initials(str))
                   else
                     str.gsub(/[^a-zA-Z0-9\.+_]/, '')
                   end
    return_value
  end

  def this_branch_folder
    if !@tag_name.nil? && @tag_name != ''
      add_dashes(get_short_form(@tag_name))
    else
      add_dashes(get_short_form(@branch_name))
    end
  end

  def get_full_build_name(compiler)
    "#{get_short_form(@config.repository_name)}-#{@short_buildid}-#{compiler[:architecture_description]}-#{get_short_form(compiler[:description])}#{get_short_form(device_tag(compiler))}"
  end

  def this_src_dir
    if @acting_as_baseline
      File.join(Dir.pwd, 'clone_baseline')
    else
      File.join(Dir.pwd, 'clone_branch')
    end
  end

  def this_build_dir
    "#{this_src_dir}/build"
  end

  def this_regression_dir
    File.join(Dir.pwd, 'clone_regressions')
  end

  def do_build(compiler, regression_baseline, flags = { :release => false })
    src_dir = this_src_dir
    build_dir = this_build_dir

    checkout_succeeded = checkout src_dir

    if compiler[:name] == 'custom_check'
      start_time = Time.now
      @test_results = custom_check @config, compiler, src_dir, build_dir

      @build_time = 0 if @build_time.nil?
      # handle the case where build is called more than once
      @build_time += (Time.now - start_time)
    elsif compiler[:name] == 'cppcheck'
      start_time = Time.now
      cppcheck @config, compiler, src_dir, build_dir
      @build_time = 0 if @build_time.nil?
      # handle the case where build is called more than once
      @build_time += (Time.now - start_time)
    else
      case @config.engine
      when 'cmake'
        start_time = Time.now
        cmake_build compiler, src_dir, build_dir, compiler[:build_type], this_regression_dir, regression_baseline, flags if checkout_succeeded
        @build_time = 0 if @build_time.nil?
        # handle the case where build is called more than once
        @build_time += (Time.now - start_time)
      else
        raise 'Unknown Build Engine'
      end
    end
  end

  def do_test(compiler, regression_baseline)
    src_dir = this_src_dir
    build_dir = this_build_dir

    build_succeeded = do_build compiler, regression_baseline

    if compiler[:name] == 'cppcheck' || compiler[:name] == 'custom_check'
    else
      case @config.engine
      when 'cmake'
        start_time = Time.now
        if !ENV['DECENT_CI_SKIP_TEST']
          cmake_test compiler, src_dir, build_dir, compiler[:build_type] if build_succeeded
        else
          $logger.debug('Skipping test, DECENT_CI_SKIP_TEST is set in the environment')
        end
        @test_time = 0 if @test_time.nil?
        # handle the case where test is called more than once
        @test_time += (Time.now - start_time)
      else
        raise 'Unknown Build Engine'
      end
    end
  end

  def needs_regression_test(compiler)
    (!@config.regression_script.nil? || !@config.regression_repository.nil?) && !compiler[:analyze_only] && !ENV['DECENT_CI_SKIP_REGRESSIONS'] && !compiler[:skip_regression]
  end

  def clone_regression_repository
    regression_dir = this_regression_dir
    FileUtils.mkdir_p regression_dir
    return if @config.regression_repository.nil?

    if !@config.regression_commit_sha.nil? && @config.regression_commit_sha != ''
      refspec = @config.regression_commit_sha
    elsif !@config.regression_branch.nil? && @config.regression_branch != ''
      refspec = @config.regression_branch
    else
      $logger.debug('No regression repository checkout info!?!')
      return
    end
    run_script(
      @config,
      [
        "cd #{regression_dir} && git init",
        "cd #{regression_dir} && git fetch https://#{@config.token}@github.com/#{@config.regression_repository} #{refspec}",
        "cd #{regression_dir} && git checkout FETCH_HEAD"
      ]
    )
  end

  def unhandled_failure(exc)
    @failure = exc
  end

  def inspect
    hash = {}
    instance_variables.each { |var| hash[var.to_s.delete('@')] = instance_variable_get(var) }
    hash
  end

  def next_build
    @package_location = nil
    @test_results = nil
    @test_messages = []
    @build_results = SortedSet.new
    @package_results = SortedSet.new
    @dateprefix = nil
    @failure = nil
    @build_time = nil
    @test_time = nil
    @test_run = false
    @package_time = nil
    @install_time = nil
    @performance_results = nil
    @coverage_lines = 0
    @coverage_total_lines = 0
    @coverage_functions = 0
    @coverage_total_functions = 0
    @coverage_url = nil
    @asset_url = nil
    @acting_as_baseline = false
  end

  def parse_call_grind(build_dir, file)
    object_files = {}
    source_files = {}
    functions = {}
    props = {}

    get_name = lambda do |files, id, name|
      if name.nil? || name == ''
        return_value = files[id]
      elsif id.nil?
        return_value = name
      else
        files[id] = name
        return_value = name
      end
      return_value
    end

    object_file = nil
    source_file = nil
    call_count = nil
    called_object_file = nil
    called_source_file = nil
    called_function_name = nil
    called_functions = {}

    IO.foreach(file) do |line|
      if /^(?<field>[a-z]+): (?<data>.*)/ =~ line
        props[field] = if field == 'totals'
                         data.to_i
                       else
                         data
                       end
      elsif /^ob=(?<objectfileid>\([0-9]+\))?\s*(?<objectfilename>.*)?/ =~ line
        object_file = get_name.call(object_files, objectfileid, objectfilename)
      elsif /^fl=(?<sourcefileid>\([0-9]+\))?\s*(?<sourcefilename>.*)?/ =~ line
        source_file = get_name.call(source_files, sourcefileid, sourcefilename)
      elsif /^(fe|fi)=(?<sourcefileid>\([0-9]+\))?\s*(?<sourcefilename>.*)?/ =~ line
        get_name.call(source_files, sourcefileid, sourcefilename)
      elsif /^fn=(?<functionid>\([0-9]+\))?\s*(?<functionname>.*)?/ =~ line
        get_name.call(functions, functionid, functionname)
      elsif /^cob=(?<calledobjectfileid>\([0-9]+\))?\s*(?<calledobjectfilename>.*)?/ =~ line
        called_object_file = get_name.call(object_files, calledobjectfileid, calledobjectfilename)
      elsif /^(cfi|cfl)=(?<calledsourcefileid>\([0-9]+\))?\s*(?<calledsourcefilename>.*)?/ =~ line
        called_source_file = get_name.call(source_files, calledsourcefileid, calledsourcefilename)
      elsif /^cfn=(?<calledfunctionid>\([0-9]+\))?\s*(?<calledfunctionname>.*)?/ =~ line
        called_function_name = get_name.call(functions, calledfunctionid, calledfunctionname)
      elsif /^calls=(?<count>[0-9]+)?\s+(?<target_position>[0-9]+)/ =~ line # rubocop:disable Lint/UselessAssignment
        call_count = count
      elsif /^(?<subposition>(((\+|-)?[0-9]+)|\*)) (?<cost>[0-9]+)/ =~ line # rubocop:disable Lint/UselessAssignment
        unless call_count.nil?
          this_object_file = called_object_file.nil? ? object_file : called_object_file
          this_source_file = called_source_file.nil? ? source_file : called_source_file

          called_func_is_nil = called_functions[[this_object_file, this_source_file, called_function_name]].nil?
          called_functions[[this_object_file, this_source_file, called_function_name]] = { 'count' => 0, 'cost' => 0 } if called_func_is_nil

          called_functions[[this_object_file, this_source_file, called_function_name]]['count'] += call_count.to_i
          called_functions[[this_object_file, this_source_file, called_function_name]]['cost'] += cost.to_i

          call_count = nil
          called_object_file = nil
          called_source_file = nil
          called_function_name = nil
        end
      elsif line == "\n"
      end
    end

    props['object_files'] = []

    object_files.values.each do |this_file|
      abs_path = File.absolute_path(this_file, build_dir)
      next unless abs_path.start_with?(File.absolute_path(build_dir)) && File.exist?(abs_path)

      # is in subdir?
      $logger.info("Path: #{abs_path}  build_dir #{build_dir}")
      props['object_files'] << { 'name' => Pathname.new(abs_path).relative_path_from(Pathname.new(build_dir)).to_s, 'size' => File.size(abs_path) }
    end

    most_expensive = called_functions.sort_by { |_, v| v['cost'] }.reverse.slice(0, 50)
    most_called = called_functions.sort_by { |_, v| v['count'] }.reverse.slice(0, 50)

    important_functions = Hash[most_expensive].merge(Hash[most_called]).collect { |k, v| { 'object_file' => k[0], 'source_file' => k[1], 'function_name' => k[2] }.merge(v) }

    props.merge('data' => important_functions)
  end

  def collect_performance_results
    build_dir = File.absolute_path(this_build_dir)

    results = { 'object_files' => [], 'test_files' => [] }

    Dir[build_dir + '/**/callgrind.*'].each do |file|
      performance_test_name = file.sub(/.*callgrind\./, '')
      call_grind_output = parse_call_grind(build_dir, file)
      object_files = call_grind_output.delete('object_files')
      $logger.info("Object files: #{object_files}")

      results['object_files'].concat(object_files)
      call_grind_output['test_name'] = performance_test_name
      results['test_files'] << call_grind_output
    end

    results['object_files'].uniq!

    @performance_results = results
  end

  def post_results(compiler, pending)
    @dateprefix = DateTime.now.utc.strftime('%F') if @dateprefix.nil?

    unless @test_run
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
            response = github_query(@client) { @client.upload_asset(@release_url, @package_location, :content_type => compiler[:package_mimetype], :name => asset_name) }
          rescue => e
            if try_num.zero? && e.to_s.include?('already_exists')
              $logger.error('already_exists error on 0th attempt, fatal, we shall not overwrite existing upload')
              @package_results << CodeMessage.new('CMakeLists.txt', 1, 0, 'error', "Error, asset already_exists on 0th try, refusing to upload asset: #{e}")
              fatal_failure = true
              try_num += 1
              next
            else
              $logger.error("Error uploading asset, trying again: #{e}")
              @package_results << CodeMessage.new('CMakeLists.txt', 1, 0, 'warning', "Error while attempting to upload release asset.\nDuring attempt #{try_num}\n#{e}")
            end
          end

          if response && response.state != 'new'
            $logger.info("Asset upload appears to have succeeded. url: #{response.url}, state: #{response.state}")
            succeeded = true
          else
            $logger.error('Asset upload appears to have failed, going to try and delete the failed bits.')
            asset_url = nil

            if !response.nil? && response.state == 'new'
              $logger.error("Error uploading asset #{response.url}")
              asset_url = response.url
            end

            if asset_url.nil?
              $logger.error('nil response, attempting to find release url')
              assets = github_query(@client) { @client.release_assets(@release_url) }

              assets.each do |a|
                if a.name == asset_name
                  asset_url = a.url
                  break
                end
              end
            end

            if asset_url
              $logger.error("Found release url in list of assets: #{asset_url}")
              $logger.error("Deleting existing asset_url and trying again #{asset_url}")
              @package_results << CodeMessage.new('CMakeLists.txt', 1, 0, 'warning', "Error attempting to upload release asset, deleting and trying again. #{asset_url}\nDuring attempt #{try_num}")
              begin
                github_query(@client) { @client.delete_release_asset(asset_url) }
              rescue => e
                $logger.error("Error deleting failed asset, continuing to next try #{e}")
                @package_results << CodeMessage.new('CMakeLists.txt', 1, 0, 'warning', "Error attempting to delete failed release asset upload.\nDuring attempt #{try_num}\nRelease asset #{e}")
              end
            end
          end

          try_num += 1
        end

        unless succeeded
          $logger.error("After #{try_num} tries we still failed to upload the release asset.")
          @package_results << CodeMessage.new('CMakeLists.txt', 1, 0, 'error', "#{try_num} attempts where made to upload release assets and all failed")
        end

      end
    end

    test_results_data = []

    test_results_passed = 0
    test_results_total = 0
    test_results_warning = 0

    test_results_failure_counts = {}

    @test_results&.each do |t|
      test_results_total += 1
      test_results_passed += 1 if t.passed
      test_results_warning += 1 if t.warning

      category_index = t.name.index('.')
      category_name = 'Uncategorized'
      category_name = t.name.slice(0, category_index) unless category_index.nil?

      failure_type = t.passed ? 'Passed' : t.failure_type

      if test_results_failure_counts[category_name].nil?
        category = {}
        category.default = 0
        test_results_failure_counts[category_name] = category
      end

      test_results_failure_counts[category_name][failure_type] += 1

      test_results_data << t.inspect
    end

    build_errors = 0
    build_warnings = 0
    build_results_data = []

    unless @build_results.nil?
      @build_results.each do |b|
        build_errors += 1 if b.error?
        build_results_data << b.inspect
      end
      build_warnings = @build_results.count - build_errors
    end

    package_errors = 0
    package_warnings = 0
    package_results_data = []

    @package_results&.each do |b|
      package_errors += 1 if b.error?
      package_warnings += 1 if b.warning?

      package_results_data << b.inspect
    end

    performance_total_time = nil
    performance_test_count = 0

    unless @performance_results.nil?
      performance_total_time = 0

      @performance_results['test_files'].each do |v|
        performance_test_count += 1
        performance_total_time += v['totals'] unless v['totals'].nil?
      end
    end

    yaml_data = {
      'title' => build_base_name(compiler),
      'permalink' => "#{build_base_name(compiler)}.html",
      'tags' => 'data',
      'layout' => 'ci_results',
      'date' => DateTime.now.utc.strftime('%F %T'),
      'unhandled_failure' => !@failure.nil?,
      'build_error_count' => build_errors,
      'build_warning_count' => build_warnings,
      'package_error_count' => package_errors,
      'package_warning_count' => package_warnings,
      'test_count' => test_results_total,
      'test_passed_count' => test_results_passed,
      'repository' => @repository,
      'compiler' => compiler[:name],
      'compiler_version' => compiler[:version],
      'architecture' => compiler[:architecture],
      'os' => @config.os,
      'os_release' => @config.os_release,
      'is_release' => release?,
      'release_packaged' => !@package_location.nil?,
      'packaging_skipped' => compiler[:skip_packaging],
      'package_name' => @package_location.nil? ? nil : Pathname.new(@package_location).basename,
      'tag_name' => @tag_name,
      'commit_sha' => @commit_sha,
      'branch_name' => @branch_name,
      'test_run' => !@test_results.nil?,
      'pull_request_issue_id' => pull_request_issue_id.to_s,
      'pull_request_base_repository' => @pull_request_base_repository.to_s,
      'pull_request_base_ref' => @pull_request_base_ref.to_s,
      'device_id' => (device_id compiler).to_s,
      'pending' => pending,
      'analyze_only' => compiler[:analyze_only],
      'build_time' => @build_time,
      'test_time' => @test_time,
      'package_time' => @package_time,
      'install_time' => @install_time,
      'results_repository' => @config.results_repository.to_s,
      'machine_name' => Socket.gethostname.to_s,
      'machine_ip' => Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address.to_s,
      'test_pass_limit' => @config.test_pass_limit,
      'test_warn_limit' => @config.test_warn_limit,
      'coverage_enabled' => compiler[:coverage_enabled],
      'coverage_pass_limit' => compiler[:coverage_pass_limit],
      'coverage_warn_limit' => compiler[:coverage_warn_limit],
      'coverage_lines' => @coverage_lines,
      'coverage_total_lines' => @coverage_total_lines,
      'coverage_functions' => @coverage_functions,
      'coverage_total_functions' => @coverage_total_functions,
      'coverage_url' => @coverage_url,
      'asset_url' => @asset_url,
      'performance_total_time' => performance_total_time,
      'performance_test_count' => performance_test_count
    }

    json_data = {
      'build_results' => build_results_data,
      'test_results' => test_results_data,
      'failure' => @failure,
      'package_results' => package_results_data,
      'configuration' => yaml_data,
      'performance_results' => @performance_results
    }

    json_document =
      <<-YAML
#{yaml_data.to_yaml}
---
#{JSON.pretty_generate(json_data)}
      YAML

    test_failed = false
    if @test_results.nil?
      test_color = 'red'
      test_failed = true
      test_string = 'NA'
    else
      test_percent = if test_results_total.zero?
                       100.0
                     else
                       (test_results_passed.to_f / test_results_total.to_f) * 100.0
                     end

      if test_percent > @config.test_pass_limit
        test_color = 'green'
      elsif test_percent > @config.test_warn_limit
        test_color = 'yellow'
      else
        test_color = 'red'
        test_failed = true
      end
      test_string = "#{test_percent.round(2)}%25"
    end

    test_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Test Badge](http://img.shields.io/badge/tests%20passed-#{test_string}-#{test_color}.png)</a>"

    if compiler[:analyze_only]
      test_failed = false
      test_badge = ''
    end

    build_failed = false
    if build_errors.positive?
      build_color = 'red'
      build_string = 'failing'
      build_failed = true
    elsif build_warnings.positive?
      build_color = 'yellow'
      build_string = 'warnings'
    else
      build_color = 'green'
      build_string = 'passing'
    end

    build_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Build Badge](http://img.shields.io/badge/build%20status-#{build_string}-#{build_color}.png)</a>"

    cov_failed = false
    coverage_badge = ''

    if compiler[:coverage_enabled]
      coverage_percent = if @coverage_total_lines.zero?
                           0
                         else
                           (@coverage_lines.to_f / @coverage_total_lines.to_f) * 100.0
                         end

      if coverage_percent >= compiler[:coverage_pass_limit]
        cov_color = 'green'
      elsif coverage_percent >= compiler[:coverage_warn_limit]
        cov_color = 'yellow'
      else
        cov_color = 'red'
        cov_failed = true
      end
      cov_str = "#{coverage_percent.round(2)}%25"

      coverage_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Coverage Badge](http://img.shields.io/badge/coverage%20status-#{cov_str}-#{cov_color}.png)</a>"
    end

    github_status = if pending
                      'pending'
                    elsif build_failed || test_failed || cov_failed || !@failure.nil?
                      'failure'
                    else
                      'success'
                    end

    github_status_message = if pending
                              'Build Pending'
                            elsif build_failed
                              'Build Failed'
                            elsif test_failed
                              "Tests Failed (#{test_results_passed} of #{test_results_total} tests passed, #{test_results_warning} test warnings)"
                            elsif cov_failed
                              'Coverage Too Low'
                            else
                              "OK (#{test_results_passed} of #{test_results_total} tests passed, #{test_results_warning} test warnings)"
                            end

    message_counts = Hash.new(0)
    @test_messages.each { |x| message_counts[x.message] += 1 }

    $logger.debug("Message counts loaded: #{message_counts}")

    message_counts_str = ''
    message_counts.each do |message, count|
      message_counts_str += if count > 1
                              " * #{count} tests had: #{message}\n"
                            else
                              " * 1 test had: #{message}\n"
                            end
    end

    $logger.debug("Message counts string: #{message_counts_str}")

    test_failures_counts_str = ''
    test_results_failure_counts.sort { |a, b| a[0].casecmp(b[0]) }.each do |category, value|
      next if value.size <= 1

      test_failures_counts_str += "\n#{category} Test Summary\n"
      sorted_values = value.sort do |a, b|
        if a[0] == 'Passed'
          -1
        else
          b[0] == 'Passed' ? 1 : a[0].casecmp(b[0])
        end
      end
      sorted_values.each do |failure, count|
        test_failures_counts_str += " * #{failure}: #{count}\n"
      end
    end

    github_document = if !@failure.nil?
                        <<-GIT
<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>Unhandled Failure</a>
                        GIT
                      else
                        <<-GIT
#{@refspec} (#{@author}) - #{device_id compiler}: #{github_status_message}

#{message_counts_str == '' ? '' : 'Messages:\n'}
#{message_counts_str}
#{test_failures_counts_str == '' ? '' : 'Failures:\n'}
#{test_failures_counts_str}

#{build_badge} #{test_badge} #{coverage_badge}
                        GIT
                      end

    if !@test_run
      begin
        if pending
          $logger.info('Posting pending results file')
          response = github_query(@client) do
            @client.create_contents(
              @config.results_repository,
              "#{@config.results_path}/#{this_branch_folder}/#{@dateprefix}-#{results_file_name compiler}",
              "#{Socket.gethostname}: Commit initial build results file: #{@dateprefix}-#{results_file_name compiler}",
              json_document
            )
          end

          $logger.debug("Results document sha set: #{response.content.sha}")
          @results_document_sha = response.content.sha
        else
          raise 'Error, no prior results document sha set' if @results_document_sha.nil?

          $logger.info("Updating contents with sha #{@results_document_sha}")
          github_query(@client) do
            @client.update_contents(
              @config.results_repository,
              "#{@config.results_path}/#{this_branch_folder}/#{@dateprefix}-#{results_file_name compiler}",
              "#{Socket.gethostname}: Commit final build results file: #{@dateprefix}-#{results_file_name compiler}",
              @results_document_sha,
              json_document
            )
          end
        end
      rescue => e
        $logger.error "Error creating / updating results contents file: #{e}"
        raise e
      end

      if !pending && @config.post_results_comment
        if !@commit_sha.nil? && @repository == @config.repository
          github_query(@client) { @client.create_commit_comment(@config.repository, @commit_sha, github_document) }
        elsif !pull_request_issue_id.nil?
          github_query(@client) { @client.add_comment(@config.repository, pull_request_issue_id, github_document) }
        end
      end

      if !@commit_sha.nil? && @config.post_results_status
        if !@pull_request_base_repository.nil?
          github_query(@client) do
            @client.create_status(
              @pull_request_base_repository,
              @commit_sha,
              github_status,
              :context => device_id(compiler), :target_url => "#{@config.results_base_url}/#{build_base_name compiler}.html", :description => github_status_message
            )
          end
        else
          github_query(@client) do
            @client.create_status(
              @config.repository,
              @commit_sha,
              github_status,
              :context => device_id(compiler), :target_url => "#{@config.results_base_url}/#{build_base_name compiler}.html", :description => github_status_message
            )
          end
        end
      end

    else
      File.open("#{@dateprefix}-#{results_file_name compiler}", 'w+') { |f| f.write(json_document) }
      File.open("#{@dateprefix}-COMMENT-#{results_file_name compiler}", 'w+') { |f| f.write(github_document) }
    end
  end
end
