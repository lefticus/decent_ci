# encoding: UTF-8 

require 'fileutils'
require_relative 'testresult.rb'

# contains functions necessary for working with the 'cmake' engine
module CustomCheck
  def custom_check(compiler, src_dir, build_dir)

    test_results = []
    compiler[:commands].each {|command|
      compiler_flags = "#{build_dir}"
      unless File.directory?(build_dir)
        FileUtils.mkdir_p(build_dir)
      end
      begin
        out, err, result = run_script(["cd #{src_dir} && #{command} #{compiler_flags}"])
      rescue
        test_results.push(TestResult.new(command, 'failed', 0, 'Could not run file, check permissions, executable bit, etc.', [], ''))
      end

      # expected fields to be read: "tool", "file", "line", "column" (optional), "message_type", "message", "id" (optional)
      if process_custom_check_results(compiler, src_dir, build_dir, out, err, result)
        test_results.push(TestResult.new(command, 'passed', 0, '', [], ''))
      else
        test_results.push(TestResult.new(command, 'failed', 0, '', [], ''))
      end
    }

    return test_results
  end
end

