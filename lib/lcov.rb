# frozen_string_literal: true

# contains functions necessary for working with the 'lcov' coverage generation tool
module Lcov
  def lcov(compiler, build_dir)
    lcov_flags = "-c -d . -o ./lcov.output --no-external --base-directory ../#{compiler[:coverage_base_dir]}"
    run_script(["cd #{build_dir} && lcov #{lcov_flags}"])
    run_script(["cd #{build_dir} && lcov -r ./lcov.output `pwd`/\\* -o ./lcov.output.filtered"])
    gen_html_flags = "./lcov.output.filtered -o lcov-html --demangle-cpp --function-coverage --rc genhtml_hi_limit=#{compiler[:coverage_pass_limit]}  --rc genhtml_med_limit=#{compiler[:coverage_warn_limit]}"
    out, = run_script(["cd #{build_dir} && genhtml #{gen_html_flags}"])
    process_lcov_results(out)
  end
end
