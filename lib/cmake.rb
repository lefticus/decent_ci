# encoding: UTF-8 

# contains functions necessary for working with the 'cmake' engine
module CMake
  def cmake_build(compiler, src_dir, build_dir, build_type)
    FileUtils.mkdir_p build_dir

    cmake_flags = "#{compiler[:cmake_extra_flags]} "

    if !compiler[:cc_bin].nil?
      cmake_flags = "-DCMAKE_C_COMPILER:PATH=\"#{compiler[:cc_bin]}\" -DCMAKE_CXX_COMPILER:PATH=\"#{compiler[:cxx_bin]}\""
    else
      cmake_flags = " -DCMAKE_CXX_FLAGS=\"/FC\" -DCMAKE_C_FLAGS=\"/FC\" "
    end

    out, err, result = run_script(
      ["cd #{build_dir} && #{@config.cmake_bin} ../ #{cmake_flags} -DCPACK_PACKAGE_FILE_NAME:STRING=#{package_name compiler} -DCMAKE_BUILD_TYPE:STRING=#{build_type} -G \"#{compiler[:build_generator]}\""])


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
    pack_stdout, pack_stderr, pack_result = run_script(
      ["cd #{build_dir} && #{@config.cpack_bin} -G #{compiler[:build_package_generator]} -C #{build_type}"])

    cmake_result = process_cmake_results(compiler, src_dir, build_dir, pack_stdout, pack_stderr, pack_result, true)

    if !cmake_result
      raise "Error building package: #{pack_stderr}"
    end

    return "#{build_dir}/#{package_full_name compiler}"
  end


  def cmake_test(compiler, src_dir, build_dir, build_type)
    test_stdout, test_stderr, test_result = run_script(["cd #{build_dir} && #{@config.ctest_bin} --timeout 3600 -D ExperimentalTest -C #{build_type}"]);
    @test_results = process_ctest_results compiler, src_dir, build_dir, test_stdout, test_stderr, test_result
  end

end
