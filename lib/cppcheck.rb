# encoding: UTF-8 

# contains functions necessary for working with the 'cmake' engine
module Cppcheck
  def cppcheck(compiler, src_dir, build_dir)
    compiler_flags = "-j#{compiler[:num_parallel_builds]} --template='[{file}]:{line}:{severity}:{message}' #{compiler[:compiler_extra_flags]} ."
    out, err, result = run_script(
      ["cd #{src_dir} && #{compiler[:bin]} #{compiler_flags}"])
    return process_cppcheck_results(compiler, src_dir, build_dir, out, err, result)
  end
end

