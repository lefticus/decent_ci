# frozen_string_literal: true

require 'runners'

# contains functions necessary for working with the 'lcov' coverage generation tool
module Lcov
  include Runners

  def generate_base_command_line(compiler, build_dir)
    lcov_flags = "-c -d . -o ./lcov.output --no-external --base-directory ../#{compiler[:coverage_base_dir]}"
    "cd #{build_dir} && lcov #{lcov_flags}"
  end

  def generate_filter_command_line(build_dir)
    "cd #{build_dir} && lcov -r ./lcov.output `pwd`/\\* -o ./lcov.output.filtered"
  end

  def generate_html_command_line(compiler, build_dir)
    pass_limit = compiler[:coverage_pass_limit]
    warn_limit = compiler[:coverage_warn_limit]
    gen_html_flags = "./lcov.output.filtered -o lcov-html --demangle-cpp --function-coverage --rc genhtml_hi_limit=#{pass_limit}  --rc genhtml_med_limit=#{warn_limit}"
    "cd #{build_dir} && genhtml #{gen_html_flags}"
  end

  def lcov(this_config, compiler, build_dir)
    run_script(this_config, [generate_base_command_line(compiler, build_dir)])
    run_script(this_config, [generate_filter_command_line(build_dir)])
    out, = run_script(this_config, [generate_html_command_line(compiler, build_dir)])
    process_lcov_results(out)
  end
end
