# frozen_string_literal: true

require 'open3'

# captures functions to run commands on the system
module Runners
  def run_scripts(this_config, commands, env = {})
    all_out = String.new # rubocop:disable Performance/UnfreezeString: Too much burden to unfreeze everywhere
    all_err = String.new # rubocop:disable Performance/UnfreezeString:
    all_result = 0

    commands.each do |cmd|
      out_this_cmd, err_this_cmd, result_this_command = run_single_script(this_config, cmd, env)

      $logger.error("Error running script command: #{cmd}") unless result_this_command.exitstatus.zero?

      all_out += out_this_cmd
      all_err += err_this_cmd
      all_result += result_this_command.exitstatus
    end

    raise all_err if all_result.positive? # TODO: I don't think we should raise

    [all_out, all_err, all_result]
  end

  def run_single_script(this_config, cmd, env)
    if this_config.os == 'Windows'
      # :nocov: Not testing on Windows
      $logger.debug 'Unable to set timeout for process execution on windows'
      stdout, stderr, result = Open3.capture3(env, cmd)
      # :nocov:
    else
      # allow up to 6 hours
      stdout, stderr, result = run_with_timeout(env, cmd, 60 * 60 * 6)
    end

    stderr.encode('UTF-8', :invalid => :replace).split("\n").each do |l|
      $logger.debug("cmd: #{cmd}: stderr: #{l}")
    end

    [stdout, stderr, result]
  end

  # originally from https://gist.github.com/lpar/1032297
  # runs a specified shell command in a separate thread.
  # If it exceeds the given timeout in seconds, kills it.
  # Returns any output produced by the command (stdout or stderr) as a String.
  # Uses Kernel.select to wait up to the tick length (in seconds) between
  # checks on the command's status
  #
  # If you've got a cleaner way of doing this, I'd be interested to see it.
  # If you think you can do it with Ruby's Timeout module, think again.
  def run_with_timeout(env, command, timeout = 60 * 60 * 4, tick = 2)
    begin
      # Start task in another thread, which spawns a process
      stdin, stdout, stderr, thread = Open3.popen3(env, command)
      # Start watching the original running thread and watching output
      out, err = monitor_thread_state(timeout, thread, tick, stdout, stderr)
    ensure
      stdin&.close
      stdout&.close
      stderr&.close
    end
    [out.force_encoding('UTF-8'), err.force_encoding('UTF-8'), thread.value]
  end

  def monitor_thread_state(timeout, thread, tick, stdout, stderr)
    pid = thread[:pid]
    start = Time.now
    out = String.new # rubocop:disable Performance/UnfreezeString:
    err = String.new # rubocop:disable Performance/UnfreezeString:
    while (Time.now - start) < timeout && thread.alive?
      out, err, this_break = read_state_singular(stdout, stderr, tick, out, err)
      break if this_break
    end

    # Give Ruby time to clean up the other thread
    sleep 1

    if thread.alive?
      # We need to kill the process, because killing the thread leaves
      # the process alive but detached, annoyingly enough.
      # :nocov: I cannot figure out how to reproduce this right now
      Process.kill('TERM', pid)
      # :nocov:
    end
    [out, err]
  end

  def read_state_singular(stdout, stderr, tick, out, err)
    this_break = false
    # Wait up to `tick` seconds for output/error data
    rs, = Kernel.select([stdout, stderr], nil, nil, tick)
    # Try to read the data
    begin
      rs&.each do |r|
        if r == stdout
          out << stdout.read_nonblock(4096)
        elsif r == stderr
          err << stderr.read_nonblock(4096)
        end
      end
    rescue IO::WaitReadable # rubocop:disable Lint/HandleExceptions
      # A read would block, so loop around for another select
    rescue EOFError
      # Command has completed, not really an error...
      this_break = true
    end
    [out, err, this_break]
  end
end
