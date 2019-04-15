# frozen_string_literal: true

# captures functions to run commands on the system
module Runners
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
      # Get the pid of the spawned process
      pid = thread[:pid]
      start = Time.now
      out, err = _run_with_timeout_internal(pid, start, timeout, thread, tick, stdout, stderr)
    ensure
      stdin&.close
      stdout&.close
      stderr&.close
    end
    [(+out).force_encoding('UTF-8'), (+err).force_encoding('UTF-8'), thread.value]
  end

  def _run_with_timeout_tick(stdout, stderr, tick, out, err)
    this_break = false
    # Wait up to `tick` seconds for output/error data
    rs, = Kernel.select([stdout, stderr], nil, nil, tick)
    # Try to read the data
    begin
      rs&.each do |r|
        if r == stdout
          +out << stdout.read_nonblock(4096)
        elsif r == stderr
          +err << stderr.read_nonblock(4096)
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

  def _run_with_timeout_internal(pid, start, timeout, thread, tick, stdout, stderr)
    out = ''
    err = ''
    while (Time.now - start) < timeout && thread.alive?
      out, err, this_break = _run_with_timeout_tick(stdout, stderr, tick, out, err)
      break if this_break
    end

    # Give Ruby time to clean up the other thread
    sleep 1

    if thread.alive?
      # We need to kill the process, because killing the thread leaves
      # the process alive but detached, annoyingly enough.
      Process.kill('TERM', pid)
    end
    [out, err]
  end

  def _run_script(this_config, cmd, env, all_out, all_err, all_result, last_command)
    if this_config.os == 'Windows'
      $logger.warn 'Unable to set timeout for process execution on windows'
      stdout, stderr, result = Open3.capture3(env, cmd)
    else
      # allow up to 6 hours
      stdout, stderr, result = run_with_timeout(env, cmd, 60 * 60 * 6)
    end

    # stdout.encode('UTF-8', :invalid => :replace).split("\n").each do |l|
    #   $logger.debug("cmd: #{cmd}: stdout: #{l}")
    # end

    stderr.encode('UTF-8', :invalid => :replace).split("\n").each do |l|
      $logger.info("cmd: #{cmd}: stderr: #{l}")
    end

    if last_command && result != 0
      $logger.error("Error running script command: #{stderr}")
      raise stderr
    end

    all_out += stdout
    all_err += stderr

    if result&.exitstatus
      all_result += result.exitstatus
    else
      # any old failure result will do
      all_result = 1
    end

    [all_out, all_err, all_result]
  end

  def run_scripts(this_config, commands, env = {})
    all_out = ''
    all_err = ''
    all_result = 0

    commands.each do |cmd|
      all_out, all_err, all_result = _run_script(this_config, cmd, env, all_out, all_err, all_result, cmd == commands.last)
    end

    [all_out, all_err, all_result]
  end
end
