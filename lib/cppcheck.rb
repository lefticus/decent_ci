# frozen_string_literal: true

# contains functions necessary for working with the 'cppcheck' tool
module Cppcheck
  def cppcheck(compiler, src_dir, build_dir)
    compiler_flags = "-j#{compiler[:num_parallel_builds]} --template='[{file}]:{line}:{severity}:{message}' #{compiler[:compiler_extra_flags]} ."
    _, err, result = run_script(["cd #{src_dir} && #{compiler[:bin]} #{compiler_flags}"])
    process_cppcheck_results(src_dir, build_dir, err, result)
  end
end
