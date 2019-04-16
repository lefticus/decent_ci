# frozen_string_literal: true

require_relative 'runners'

# simple data class for passing args into cmake_build
class CMakeBuildArgs
  attr_reader :build_type
  attr_reader :this_device_id
  attr_reader :this_running_extra
  attr_reader :is_release
  def initialize(build_type, device_id, running_extra_tests, is_release = false)
    @build_type = build_type
    @this_device_id = device_id
    @this_running_extra = running_extra_tests
    @is_release = is_release
  end
end

# contains functions necessary for working with the 'cmake' engine
module CMake
  include Runners

  def cmake_build(compiler, src_dir, build_dir, regression_dir, regression_baseline, cmake_build_args)
    FileUtils.mkdir_p build_dir

    cmake_flags = "#{compiler[:cmake_extra_flags]} -DDEVICE_ID:STRING=\"#{cmake_build_args.this_device_id}\""

    compiler_extra_flags = compiler[:compiler_extra_flags]
    compiler_extra_flags = '' if compiler_extra_flags.nil?

    if cmake_build_args.this_running_extra
      cmake_flags = cmake_flags + ' ' + @config.extra_tests_cmake_extra_flags unless @config.extra_tests_cmake_extra_flags.nil?
    end

    if cmake_build_args.is_release
      extra_flags = compiler[:release_build_cmake_extra_flags]
      cmake_flags = cmake_flags + ' ' + extra_flags unless extra_flags.nil?
    end

    if !compiler[:cc_bin].nil?
      cmake_flags = "-DCMAKE_C_COMPILER:PATH=\"#{compiler[:cc_bin]}\" -DCMAKE_CXX_COMPILER:PATH=\"#{compiler[:cxx_bin]}\" #{cmake_flags}"
      env = {
        'CXXFLAGS' => compiler_extra_flags.to_s,
        'CFLAGS' => compiler_extra_flags.to_s,
        'CCACHE_BASEDIR' => build_dir,
        'CCACHE_UNIFY' => 'true',
        'CCACHE_SLOPPINESS' => 'include_file_mtime',
        'CC' => compiler[:cc_bin],
        'CXX' => compiler[:cxx_bin]
      }
    else
      env = {
        'CXXFLAGS' => "/FC #{compiler_extra_flags}",
        'CFLAGS' => "/FC #{compiler_extra_flags}",
        'CCACHE_BASEDIR' => build_dir,
        'CCACHE_UNIFY' => 'true',
        'CCACHE_SLOPPINESS' => 'include_file_mtime'
      }
    end

    env['PATH'] = cmake_remove_git_from_path(ENV['PATH'])

    if !regression_baseline.nil?
      env['REGRESSION_BASELINE'] = File.expand_path(regression_baseline.this_build_dir)
      env['REGRESSION_DIR'] = File.expand_path(regression_dir)
      env['REGRESSION_BASELINE_SHA'] = regression_baseline.commit_sha
      env['COMMIT_SHA'] = @commit_sha && @commit_sha != '' ? @commit_sha : @tag_name
    else
      env['REGRESSION_BASELINE'] = ' '
      env['REGRESSION_DIR'] = ' '
      env['REGRESSION_BASELINE_SHA'] = ' '
      env['COMMIT_SHA'] = ' '
    end

    env['GITHUB_TOKEN'] = ENV['GITHUB_TOKEN']

    if compiler[:target_arch].nil?
      _, err, result = run_scripts(
        @config,
        ["cd #{build_dir} && #{@config.cmake_bin} ../ #{cmake_flags}  -DCMAKE_BUILD_TYPE:STRING=#{cmake_build_args.build_type} -G \"#{compiler[:build_generator]}\""], env
      )
    else
      _, err, result = run_scripts(
        @config,
        ["cd #{build_dir} && #{@config.cmake_bin} ../ #{cmake_flags}  -DCMAKE_BUILD_TYPE:STRING=#{cmake_build_args.build_type} -G \"#{compiler[:build_generator]}\" -A #{compiler[:target_arch]}"], env
      )
    end

    cmake_result = process_cmake_results(src_dir, build_dir, err, result, false)

    return false unless cmake_result

    build_switches = if @config.os != 'Windows'
                       "-j#{compiler[:num_parallel_builds]}"
                     else
                       # :nocov: Not covering windows
                       ''
                       # :nocov:
                     end

    out, err, result = run_scripts(
      @config,
      ["cd #{build_dir} && #{@config.cmake_bin} --build . --config #{cmake_build_args.build_type} --use-stderr -- #{build_switches}"], env
    )

    msvc_success = process_msvc_results(src_dir, build_dir, out, result)
    gcc_success = process_gcc_results(src_dir, build_dir, err, result)
    process_cmake_results(src_dir, build_dir, err, result, false)
    process_python_results(src_dir, build_dir, out, err, result)
    msvc_success && gcc_success
  end

  def cmake_remove_git_from_path(old_path)
    # The point is to remove the git provided sh.exe from the path so that it does
    # not conflict with other operations
    if @config.os == 'Windows'
      # :nocov: Not covering Windows
      paths = old_path.split(';')
      paths.delete_if { |p| p =~ /Git/ }
      return paths.join(';')
      # :nocov:
    end

    old_path
  end

  def cmake_package(compiler, src_dir, build_dir, build_type)
    new_path = ENV['PATH']

    if @config.os == 'Windows'
      File.open("#{build_dir}/extract_linker_path.cmake", 'w+') { |f| f.write('message(STATUS "LINKER:${CMAKE_LINKER}")') }

      script_stdout, = run_scripts(@config, ["cd #{build_dir} && #{@config.cmake_bin} -P extract_linker_path.cmake ."])

      /.*LINKER:(?<linker_path>.*)/ =~ script_stdout
      $logger.debug("Parsed linker path from cmake: #{linker_path}")

      if linker_path && linker_path != ''
        p = File.dirname(linker_path)
        p = p.gsub(File::SEPARATOR, File::ALT_SEPARATOR) if File::ALT_SEPARATOR
        new_path = "#{p};#{new_path}"
      end

      new_path = cmake_remove_git_from_path(new_path)
      $logger.info("New path set for executing cpack, to help with get_requirements: #{new_path}")
    end

    if !compiler[:package_command].nil?
      pack_stdout, pack_stderr, pack_result = run_scripts(
        @config,
        ["cd #{build_dir} && #{compiler[:package_command]} "], 'PATH' => new_path
      )
    else
      pack_stdout, pack_stderr, pack_result = run_scripts(
        @config,
        ["cd #{build_dir} && #{@config.cpack_bin} -G #{compiler[:build_package_generator]} -C #{build_type} "], 'PATH' => new_path
      )
    end

    cmake_result = process_cmake_results(src_dir, build_dir, pack_stderr, pack_result, true)

    unless cmake_result
      raise "Error building package: #{pack_stderr}" if @package_results.empty?

      return nil
    end

    package_names = parse_package_names(pack_stdout)

    $logger.debug("package names parsed: #{package_names}")
    return nil if package_names.empty?

    $logger.error("More than one package name was returned #{package_names}, returning the 1st one only") if package_names.size > 1

    package_names[0]
  end

  def cmake_test(compiler, src_dir, build_dir, build_type)
    test_dirs = [@config.tests_dir]

    if running_extra_tests
      test_dirs << @config.extra_tests_test_dir unless @config.extra_tests_test_dir.nil?
    end

    ctest_filter = compiler[:ctest_filter]
    ctest_filter = '' if ctest_filter.nil?

    test_dirs.each do |test_dir|
      $logger.info("Running tests in dir: '#{test_dir}'")
      env = { 'PATH' => cmake_remove_git_from_path(ENV['PATH']) }
      _, test_stderr, test_result = run_scripts(
        @config,
        ["cd #{build_dir}/#{test_dir} && #{@config.ctest_bin} -j #{compiler[:num_parallel_builds]} --timeout 4200 --no-compress-output -D ExperimentalTest -C #{build_type} #{ctest_filter}"],
        env
      )
      test_results, test_messages = process_ctest_results src_dir, build_dir, "#{build_dir}/#{test_dir}"

      if @test_results.nil?
        @test_results = test_results
      else
        @test_results.concat(test_results)
      end

      @test_messages.concat(test_messages)

      # may as well see if there are some cmake results to pick up here
      process_cmake_results(src_dir, build_dir, test_stderr, test_result, false)
    end
  end
end
