# frozen_string_literal: true

require_relative 'resultsprocessor'
require_relative 'runners'

# contains functions necessary for working with the 'cppcheck' tool
module Cppcheck
  include Runners
  def generate_command_line(compiler, src_dir)
    compiler_flags = "-j#{compiler[:num_parallel_builds]} --template='[{file}]:{line}:{severity}:{message}' #{compiler[:compiler_extra_flags]} ."
    "cd #{src_dir} && #{compiler[:cppcheck_bin]} #{compiler_flags}"
  end

  def cppcheck(this_config, compiler, src_dir, build_dir)
    _, err, result = run_script(this_config, [generate_command_line(compiler, src_dir)])
    process_cppcheck_results(src_dir, build_dir, err, result)
  end
end
