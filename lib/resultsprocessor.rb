# frozen_string_literal: true

require 'active_support/all'
require 'find'

require_relative 'codemessage'
require_relative 'testresult'

# Implementation for parsing of build messages
module ResultsProcessor
  def relative_path(path, src_dir, build_dir)
    Pathname.new("#{src_dir}/#{path}").realpath.relative_path_from(Pathname.new(this_src_dir).realdirpath)
  rescue
    begin
      Pathname.new("#{build_dir}/#{path}").realpath.relative_path_from(Pathname.new(this_src_dir).realdirpath)
    rescue
      begin
        Pathname.new(path).realpath.relative_path_from(Pathname.new(this_src_dir).realdirpath)
      rescue
        Pathname.new(path)
      end
    end
  end

  def get_win32_filename(function, name)
    # :nocov: we don't test on windows currently
    max_path = 1024
    short_name = ' ' * max_path
    lfn_size = Win32API.new('kernel32', function, %w[P P L], 'L').call(name, short_name, max_path)
    (1..max_path).include?(lfn_size) ? short_name[0..lfn_size - 1] : name # rubocop:disable Performance/RangeInclude
    # :nocov:
  end

  def recover_file_case(name)
    if RbConfig::CONFIG['target_os'].match(/mingw|mswin/)
      # :nocov: we don't test on windows currently
      require 'win32api'

      get_short_win32_filename = lambda do |this_name|
        get_win32_filename('GetShortPathName', this_name)
      end

      get_long_win32_filename = lambda do |this_name|
        get_win32_filename('GetLongPathName', this_name)
      end

      get_long_win32_filename.call(get_short_win32_filename.call(name))
      # :nocov:
    else
      name
    end
  end

  def parse_custom_check_line(src_path, build_path, line)
    # JSON formatted output is expected here
    begin
      json = JSON.parse(line)
    rescue JSON::ParserError
      return CodeMessage.new(
        'DecentCI::resultsprocessor::parse_custom_check_line', __LINE__, 0, 'error',
        'Output of custom_check script was not formatted properly; should be individual line-by-line JSON objects'
      )
    end

    if json.is_a?(Array)
      return CodeMessage.new(
        'DecentCI::resultsprocessor::parse_custom_check_line', __LINE__, 0, 'error',
        'Output of custom_check script was not formatted properly, it was an array; should be individual line-by-line JSON objects'
      )
    end

    # a quick helper function to read the varying keys in the hash
    get_string_maybe = lambda do |hash, key, default_value = ''|
      returner = default_value
      returner = hash[key] unless hash[key].nil?
      returner
    end

    # read each string, giving a good default value
    tool = get_string_maybe.call(json, 'tool', nil)
    file = get_string_maybe.call(json, 'file', '(Unknown file)')
    line_num = get_string_maybe.call(json, 'line', 0)
    column = get_string_maybe.call(json, 'column', 0)
    messagetype = get_string_maybe.call(json, 'messagetype', 'error')
    message = get_string_maybe.call(json, 'message', '(No message)')
    id = get_string_maybe.call(json, 'id', nil)

    # make the message nice based on what keys are there
    message = "#{id} #{message}" unless id.nil?
    message = "#{tool} #{message}" unless tool.nil?

    # then just return a good codemessage
    CodeMessage.new(relative_path(file, src_path, build_path), line_num, column, messagetype, message)
  end

  def parse_cppcheck_line(src_path, build_path, line)
    /\[(?<filename>.*):(?<line_number>[0-9]+)\]: (?<message_type>\S+) (?<message>.*)/ =~ line
    message_type&.tr!('()', '')
    return CodeMessage.new(relative_path(filename, src_path, build_path), line_number, 0, message_type, message) unless filename.nil? || filename == '' || message_type.nil?

    nil
  end

  def process_custom_check_results(src_dir, build_dir, stdout, stderr, result)
    results = []
    [stdout, stderr].each do |output_stream|
      output_stream.encode('UTF-8', :invalid => :replace).split("\n").each do |line|
        next if line.strip == ''

        msg = parse_custom_check_line(src_dir, build_dir, line)
        results << msg
      end
    end
    @build_results.merge(results)
    result.zero?
  end

  def process_cppcheck_results(src_dir, build_dir, stderr, result)
    results = []
    stderr.encode('UTF-8', :invalid => :replace).split("\n").each do |line|
      next if line.strip == ''

      msg = parse_cppcheck_line(src_dir, build_dir, line)
      results << msg unless msg.nil?
    end
    @build_results.merge(results)
    result.zero?
  end

  def match_type_to_possible_fortran(err_line)
    type = 'error'
    type = 'warning' if err_line.include?('.f90') # this is a bad assumption, but right now fortran warnings are being taken as uncategorized build errors
    type
  end

  def process_cmake_results(src_dir, build_dir, stderr, cmake_exit_code, is_package)
    results = []

    file = nil
    line = nil
    msg = ''
    type = nil

    $logger.info('Parsing cmake error results')

    previous_line = ''
    last_was_error_line = false

    stderr.encode('UTF-8', :invalid => :replace).split("\n").each do |err|
      # Append next line to the message context for a CMake error
      if last_was_error_line && !results.empty?
        stripped = err.strip
        if stripped != ''
          last_item = results.last
          last_item.message = last_item.message + '; ' + stripped
          results[results.length - 1] = last_item
        end
      end

      last_was_error_line = false

      $logger.debug("Parsing cmake error Line: #{err}")
      if err.strip == ''
        if !file.nil? && !line.nil? && !msg.nil?
          results << CodeMessage.new(relative_path(file, src_dir, build_dir), line, 0, type, "#{previous_line}#{err}")
          last_was_error_line = true
        end
        file = nil
        line = nil
        msg = ''
        type = nil
      elsif file.nil?
        /^CPack Error: (?<message>.*)/ =~ err
        unless message.nil?
          results << CodeMessage.new(relative_path('CMakeLists.txt', src_dir, build_dir), 1, 0, 'error', "#{previous_line}#{err.strip}")
          last_was_error_line = true
        end

        /^CMake Error: (?<message>.*)/ =~ err
        unless message.nil?
          results << CodeMessage.new(relative_path('CMakeLists.txt', src_dir, build_dir), 1, 0, 'error', "#{previous_line}#{err.strip}")
          last_was_error_line = true
        end

        /^ERROR: (?<message>.*)/ =~ err
        unless message.nil?
          results << CodeMessage.new(relative_path('CMakeLists.txt', src_dir, build_dir), 1, 0, 'error', "#{previous_line}#{err.strip}")
          last_was_error_line = true
        end

        /^WARNING: (?<message>.*)/ =~ err
        unless message.nil?
          results << CodeMessage.new(relative_path('CMakeLists.txt', src_dir, build_dir), 1, 0, 'warning', "#{previous_line}#{err.strip}")
          last_was_error_line = true
        end

        /CMake (?<message_type>\S+) at (?<filename>.*):(?<line_number>[0-9]+) \(\S+\):$/ =~ err

        if !filename.nil? && !line_number.nil?
          file = filename
          line = line_number
          type = message_type.nil? ? 'error' : message_type.downcase
        else
          /(?<filename>.*):(?<line_number>[0-9]+):$/ =~ err

          if !filename.nil? && !line_number.nil? && (filename !~ /file included/i) && (filename !~ /^\s*from\s+/i)
            file = filename
            line = line_number
            type = match_type_to_possible_fortran(err)
          end
        end
      else
        +msg << "\n" if msg != ''
        +msg << err
      end

      previous_line = err.strip
      previous_line += '; ' if previous_line != ''
    end

    # get any lingering message from the last line
    results << CodeMessage.new(relative_path(file, src_dir, build_dir), line, 0, type, msg) if !file.nil? && !line.nil? && !msg.nil?

    results.each { |r| $logger.debug("CMake error message parsed: #{r.inspect}") }

    if is_package
      @package_results.merge(results)
    else
      @build_results.merge(results)
    end

    cmake_exit_code.zero?
  end

  def parse_generic_line(src_dir, build_dir, line)
    /\s*(?<filename>\S+):(?<line_number>[0-9]+): (?<message>.*)/ =~ line
    return CodeMessage.new(relative_path(filename, src_dir, build_dir), line_number, 0, 'error', message) if !filename.nil? && !message.nil?

    nil
  end

  def parse_msvc_line(src_dir, build_dir, line)
    return nil if line.nil?

    /(?<filename>.+)\((?<line_number>[0-9]+)\): (?<message_type>.+?) (?<message_code>\S+): (?<message>.*) \[.*\]?/ =~ line
    pattern_found = !filename.nil? && !message_type.nil?
    message_is_error = !(%w[info note].include? message_type)
    if pattern_found && message_is_error
      CodeMessage.new(relative_path(recover_file_case(filename.strip), src_dir, build_dir), line_number, 0, message_type, message_code + ' ' + message)
    else
      /(?<filename>.+) : (?<message_type>\S+) (?<message_code>\S+): (?<message>.*) \[.*\]?/ =~ line
      pattern_2_found = !filename.nil? && !message_type.nil?
      message_2_is_error = !(%w[info note].include? message_type)
      unless pattern_2_found && message_2_is_error
        # one last pattern to try, doing it brute force
        if line.index(': ') and line.index(': ').positive?
          tokens = line.split(': ')
          if tokens.length >= 3
            filename = tokens[0]
            section_two_tokens = tokens[1].split(' ')
            message_type = section_two_tokens[0]
            message_code = section_two_tokens[1]
            message = tokens[2..-1].join(': ')
          end
        end
        pattern_3_found = !filename.nil? && !message_type.nil?
        message_3_is_error = !(%w[info note].include? message_type)
        return nil unless pattern_3_found && message_3_is_error && message_code

      end
      return nil unless filename

      CodeMessage.new(relative_path(recover_file_case(filename.strip), src_dir, build_dir), 0, 0, message_type, message_code + ' ' + message)
    end
  end

  def process_msvc_results(src_dir, build_dir, stdout, msvc_exit_code)
    results = []
    stdout.encode('UTF-8', :invalid => :replace).split("\n").each do |err|
      msg = parse_msvc_line(src_dir, build_dir, err)
      results << msg unless msg.nil?
    end
    @build_results.merge(results)
    msvc_exit_code.zero?
  end

  def parse_gcc_line(src_path, build_path, line)
    # 'Something.cc:32:4: multiple definition of variable'
    /(?<filename>.*):(?<line_number>[0-9]+):(?<column_number>[0-9]+): (?<message_type>.+?): (?<message>.*)/ =~ line
    pattern_found = !filename.nil? && !message_type.nil?
    message_is_error = !(%w[info note].include? message_type)
    if pattern_found && message_is_error
      CodeMessage.new(relative_path(filename, src_path, build_path), line_number, column_number, message_type, message)
    else
      /(?<filename>.*):(?<line_number>[0-9]+): (?<message>.*)/ =~ line
      # catch linker errors
      pattern_found = !filename.nil? && !message.nil?
      linker_error = false
      linker_error = ['multiple definition', 'undefined'].any? { |word| message.include? word } unless message.nil?
      return nil unless pattern_found && linker_error

      CodeMessage.new(relative_path(filename, src_path, build_path), line_number, 0, 'error', message)
    end
  end

  def process_gcc_results(src_path, build_path, stderr, gcc_exit_code)
    results = []
    linker_msg = nil

    stderr.encode('UTF-8', :invalid => :replace).split("\n").each do |line|
      unless linker_msg.nil?
        if line.match(/^\s.*/)
          linker_msg += "\n" + line
        else
          results << CodeMessage.new('CMakeLists.txt', 0, 0, 'error', linker_msg)
          linker_msg = nil
        end
      end

      msg = parse_gcc_line(src_path, build_path, line)
      if !msg.nil?
        results << msg
      elsif line.match(/^Undefined symbols for architecture.*/)
        # try to catch some goofy clang linker errors that don't give us very much info
        linker_msg = line
      end
    end

    results << CodeMessage.new('CMakeLists.txt', 0, 0, 'error', linker_msg) unless linker_msg.nil?

    @build_results.merge(results)

    gcc_exit_code.zero?
  end

  def parse_error_messages(src_dir, build_dir, output)
    results = []
    output.encode('UTF-8', :invalid => :replace).split("\n").each do |l|
      msg = parse_gcc_line(src_dir, build_dir, l)
      msg = parse_msvc_line(src_dir, build_dir, l) if msg.nil?
      msg = parse_generic_line(src_dir, build_dir, l) if msg.nil?
      results << msg unless msg.nil?
    end
    results
  end

  def parse_python_or_latex_line(src_dir, build_dir, line)
    line_number = nil
    # Since we are just doing line-by-line parsing, it really limits what we can get, but we'll try our best anyway
    if line.include? 'LaTeX Error'
      # ! LaTeX Error: Environment itemize undefined.
      /^.*Error: (?<message>.+)/ =~ line
      compiler_string = 'LaTeX'
    else
      # assume Python
      # TypeError: cannot concatenate 'str' and 'int' objects
      /File "(?<filename>.+)", line (?<line_number>[0-9]+),.*/ =~ line
      /^.*Error: (?<message>.+)/ =~ line
      compiler_string = 'Python'
    end

    return CodeMessage.new(relative_path(filename.strip, src_dir, build_dir), line_number, 0, 'error', 'error') if !filename.nil? && !line_number.nil?

    return CodeMessage.new(relative_path(compiler_string, src_dir, build_dir), 0, 0, 'error', message) unless message.nil?

    nil
  end

  def process_python_results(src_dir, build_dir, stdout, stderr, python_exit_code)
    results = []
    stdout.encode('UTF-8', :invalid => :replace).split("\n").each do |err|
      msg = parse_python_or_latex_line(src_dir, build_dir, err)
      results << msg unless msg.nil?
    end
    $logger.debug("stdout results: #{results}")
    @build_results.merge(results)
    results = []
    stderr.encode('UTF-8', :invalid => :replace).split("\n").each do |err|
      msg = parse_python_or_latex_line(src_dir, build_dir, err)
      results << msg unless msg.nil?
    end
    $logger.debug("stderr results: #{results}")
    @build_results.merge(results)
    python_exit_code.zero?
  end

  def parse_package_names(output)
    results = []
    output.encode('UTF-8', :invalid => :replace).split("\n").each do |l|
      /CPack: - package: (?<filename>.*) generated./ =~ l
      results << filename if filename
    end
    results
  end

  def process_lcov_results(out)
    # Overall coverage rate:
    #  lines......: 67.9% (173188 of 255018 lines)
    #  functions..: 83.8% (6228 of 7433 functions)

    total_lines = 0
    covered_lines = 0
    total_functions = 0
    covered_functions = 0
    total_lines_str = nil
    covered_lines_str = nil
    total_functions_str = nil
    covered_functions_str = nil

    out.encode('UTF-8', :invalid => :replace).split("\n").each do |l|
      /.*\((?<covered_lines_str>[0-9]+) of (?<total_lines_str>[0-9]+) lines.*/ =~ l
      covered_lines = covered_lines_str.to_i unless covered_lines_str.nil?
      total_lines = total_lines_str.to_i unless total_lines_str.nil?

      /.*\((?<covered_functions_str>[0-9]+) of (?<total_functions_str>[0-9]+) functions.*/ =~ l
      covered_functions = covered_functions_str.to_i unless covered_functions_str.nil?
      total_functions = total_functions_str.to_i unless total_functions_str.nil?
    end

    [total_lines, covered_lines, total_functions, covered_functions]
  end

  def process_ctest_results(src_dir, build_dir, test_dir)
    unless File.directory?(test_dir)
      $logger.error("Error: test_dir #{test_dir} does not exist, cannot parse test results")
      return nil, []
    end

    messages = []

    Find.find(test_dir) do |path|
      next unless path.match(/.*Test.xml/)

      results = []
      # read the test.xml file but make sure to close it
      f = File.open(path, 'r')
      contents = f.read
      f.close
      # then get the XML contents into a Ruby Hash
      xml = Hash.from_xml(contents)
      test_results = xml['Site']['Testing']
      t = test_results['Test']
      unless t.nil?
        tests = []
        tests << t
        tests.flatten!

        tests.each do |n|
          $logger.debug("N: #{n}")
          $logger.debug("Results: #{n['Results']}")
          r = n['Results']
          if n['Status'] == 'notrun'
            results << TestResult.new(n['Name'], n['Status'], 0, '', nil, 'notrun')
          elsif r
            m = r['Measurement']
            value = nil
            errors = nil

            unless m.nil? || m['Value'].nil?
              value = m['Value']
              errors = parse_error_messages(src_dir, build_dir, value)
              value.split("\n").each do |line|
                if /\[decent_ci:test_result:message\] (?<message>.+)/ =~ line
                  messages << TestMessage.new(n['Name'], message)
                end
              end
            end

            nm = r['NamedMeasurement']

            unless nm.nil?
              failure_type = ''
              nm.each do |measurement|
                next if measurement['name'] != 'Exit Code'

                ft = measurement['Value']
                failure_type = ft unless ft.nil?
              end

              nm.each do |measurement|
                next if measurement['name'] != 'Execution Time'

                status_string = n['Status']
                status_string = 'warning' if !value.nil? && value =~ /\[decent_ci:test_result:warn\]/ && status_string == 'passed'
                results << TestResult.new(n['Name'], status_string, measurement['Value'], value, errors, failure_type)
              end
            end
          end
        end
      end

      return nil, messages if results.empty?

      return results, messages
    end
  end
end
