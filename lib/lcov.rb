# encoding: UTF-8 

# contains functions necessary for working with the 'cmake' engine
module Lcov
  def lcov(compiler, src_dir, build_dir)
    lcov_flags = "-c -d . -o ./lcov.output --no-external --base-directory ../#{compiler[:coverage_base_dir]}"
    out, err, result = run_script(
      ["cd #{build_dir} && lcov #{lcov_flags}"])

    out, err, result = run_script(
      ["cd #{build_dir} && lcov -r ./lcov.output `pwd`/\\* -o ./lcov.output.filtered"])

    genhtml_flags = "./lcov.output.filtered -o lcov-html --demangle-cpp --function-coverage --rc genhtml_hi_limit=#{compiler[:coverage_pass_limit]}  --rc genhtml_med_limit=#{compiler[:coverage_warn_limit]}"
    out, err, result = run_script(
      ["cd #{build_dir} && genhtml #{genhtml_flags}"])

    return process_lcov_results(compiler, src_dir, build_dir, out, err, result)
  end


end
