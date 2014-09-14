# encoding: UTF-8 

# contains functions necessary for working with the 'cmake' engine
module CMake
  def cmake_build(compiler, src_dir, build_dir, install_dir, build_type, regression_dir, regression_baseline)
    FileUtils.mkdir_p build_dir

    cmake_flags = "#{compiler[:cmake_extra_flags]} -DDEVICE_ID:STRING=\"#{device_id compiler}\""
    if install_dir
      cmake_flags += " -DCMAKE_INSTALL_PREFIX:PATH=\"#{install_dir}\""
    end

    compiler_extra_flags = compiler[:compiler_extra_flags]
    compiler_extra_flags = "" if compiler_extra_flags.nil?

    env = {}
    if !compiler[:cc_bin].nil?
      cmake_flags = "-DCMAKE_C_COMPILER:PATH=\"#{compiler[:cc_bin]}\" -DCMAKE_CXX_COMPILER:PATH=\"#{compiler[:cxx_bin]}\" #{cmake_flags}"
      env = {"CXXFLAGS"=>"#{compiler_extra_flags}", "CFLAGS"=>"#{compiler_extra_flags}", "CCACHE_BASEDIR"=>build_dir, "CCACHE_UNIFY"=>"true", "CCACHE_SLOPPINESS"=>"include_file_mtime"}
    else
      env = {"CXXFLAGS"=>"/FC #{compiler_extra_flags}", "CFLAGS"=>"/FC #{compiler_extra_flags}", "CCACHE_BASEDIR"=>build_dir, "CCACHE_UNIFY"=>"true", "CCACHE_SLOPPINESS"=>"include_file_mtime"}
    end

    if !regression_baseline.nil?
      env["REGRESSION_BASELINE"] = File.expand_path(regression_baseline.get_build_dir(compiler))
      env["REGRESSION_DIR"] = File.expand_path(regression_dir)
      env["REGRESSION_BASELINE_SHA"] = regression_baseline.commit_sha
      env["COMMIT_SHA"] = (@commit_sha && @commit_sha != "") ? @commit_sha : @tag_name
    end

    out, err, result = run_script(
      ["cd #{build_dir} && #{@config.cmake_bin} ../ #{cmake_flags}  -DCMAKE_BUILD_TYPE:STRING=#{build_type} -G \"#{compiler[:build_generator]}\""], env)


    cmake_result = process_cmake_results(compiler, src_dir, build_dir, out, err, result, false)

    if !cmake_result
      return false;
    end

    if @config.os != "Windows"
      build_switches = "-j#{compiler[:num_parallel_builds]}"
    else
      build_switches = ""
    end

    out, err, result = run_script(
        ["cd #{build_dir} && #{@config.cmake_bin} --build . --config #{build_type} --use-stderr -- #{build_switches}"])

    msvc_success = process_msvc_results(compiler, src_dir, build_dir, out, err, result)
    gcc_success = process_gcc_results(compiler, src_dir, build_dir, out, err, result)
    return msvc_success && gcc_success
  end

  def cmake_package(compiler, src_dir, build_dir, build_type)
    new_path = ENV['PATH']


    if @config.os == "Windows"
      File.open("#{build_dir}/extract_linker_path.cmake", "w+") { |f| f.write('message(STATUS "LINKER:${CMAKE_LINKER}")') }

      script_stdout, script_stderr, script_result = run_script(
		    ["cd #{build_dir} && #{@config.cmake_bin} -P extract_linker_path.cmake ."])

      /.*LINKER:(?<linker_path>.*)/ =~ script_stdout
      $logger.debug("Parsed linker path from cmake: #{linker_path}")
      
      if linker_path && linker_path != ""
        p = File.dirname(linker_path)
        p = p.gsub(File::SEPARATOR, File::ALT_SEPARATOR) if File::ALT_SEPARATOR
	new_path = "#{p};#{new_path}"
	$logger.info("New path set for executing cpack, to help with get_requirements: #{new_path}")
      end
    end

    pack_stdout, pack_stderr, pack_result = run_script(
      ["cd #{build_dir} && #{@config.cpack_bin} -G #{compiler[:build_package_generator]} -C #{build_type} "], {"PATH"=>new_path})

    cmake_result = process_cmake_results(compiler, src_dir, build_dir, pack_stdout, pack_stderr, pack_result, true)

    if !cmake_result
      if @package_results.empty?
        raise "Error building package: #{pack_stderr}"
      else 
        return nil
      end
    end

    package_names = parse_package_names(pack_stdout)

    $logger.debug("package names parsed: #{package_names}")
    if package_names.empty?
      return nil
    elsif package_names.size() > 1
      $logger.error("More than one package name was returned #{package_names}, returning the 1st one only")
    end

    return package_names[0]
  end


  def cmake_test(compiler, src_dir, build_dir, build_type)
    test_stdout, test_stderr, test_result = run_script(["cd #{build_dir}/#{@config.tests_dir} && #{@config.ctest_bin} -j #{compiler[:num_parallel_builds]} --timeout 3600 -D ExperimentalTest -C #{build_type}"]);
    @test_results = process_ctest_results compiler, src_dir, build_dir, test_stdout, test_stderr, test_result
  end

  def cmake_install(compiler, src_dir, build_dir, install_dir, build_type)
    if @config.os != "Windows"
      build_switches = "-j#{compiler[:num_parallel_builds]}"
    else
      build_switches = ""
    end

    out, err, result = run_script(
        ["cd #{build_dir} && #{@config.cmake_bin} --build . --config #{build_type} --target install --use-stderr -- #{build_switches}"])

    cmake_result = process_cmake_results(compiler, src_dir, build_dir, out, err, result, true)
    msvc_success = process_msvc_results(compiler, src_dir, build_dir, out, err, result)
    gcc_success = process_gcc_results(compiler, src_dir, build_dir, out, err, result)
    return msvc_success && gcc_success
  end


end
