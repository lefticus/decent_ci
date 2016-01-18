# encoding: UTF-8 

# contains functions necessary for working with the 'cmake' engine
module CustomCheck
  def custom_check(compiler, src_dir, build_dir)

    result = true

    compiler[:commands].each{ |command|
      compiler_flags = "#{build_dir}"
      out, err, result = run_script(
        ["cd #{src_dir} && #{command} #{compiler_flags}"])


      # expected fields to be read: "tool", "file", "line", "column" (optional), "message_type", "message", "id" (optional)
      result = result && process_custom_check_results(compiler, src_dir, build_dir, out, err, result)
    }

    return result
  end
end

