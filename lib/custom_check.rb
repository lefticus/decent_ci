# frozen_string_literal: true

require 'fileutils'
require_relative 'runners'
require_relative 'testresult.rb'

# contains functions necessary for working with the 'custom_check' scripts
module CustomCheck
  include Runners

  def custom_check(this_config, compiler, src_dir, build_dir)
    test_results = []
    compiler[:commands].each do |command|
      compiler_flags = build_dir.to_s
      FileUtils.mkdir_p(build_dir) unless File.directory?(build_dir)
      begin
        out, err, result = run_scripts(this_config, ["cd #{src_dir} && #{command} #{compiler_flags}"])
      rescue
        test_results.push(TestResult.new(command, 'failed', 0, 'Could not run file, check permissions, executable bit, etc.', [], ''))
        return test_results
      end
      # expected fields to be read: "tool", "file", "line", "column" (optional), "message_type", "message", "id" (optional)
      if process_custom_check_results(src_dir, build_dir, out, err, result)
        test_results.push(TestResult.new(command, 'passed', 0, '', [], ''))
      else
        test_results.push(TestResult.new(command, 'failed', 0, '', [], ''))
      end
    end
    test_results
  end
end
