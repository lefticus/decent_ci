# encoding: UTF-8 
#

# Implementation for parsing of build messages
module ResultsProcessor
  def relative_path(p, src_dir, build_dir, compiler)
    begin
      return Pathname.new("#{src_dir}/#{p}").realpath.relative_path_from(Pathname.new(get_src_dir compiler).realdirpath)
    rescue
      begin
        return Pathname.new("#{build_dir}/#{p}").realpath.relative_path_from(Pathname.new(get_src_dir compiler).realdirpath)
      rescue
        begin
          return Pathname.new(p).realpath.relative_path_from(Pathname.new(get_src_dir compiler).realdirpath)
        rescue
          return Pathname.new(p)
        end
      end
    end
  end

  def recover_file_case(name)
    if RbConfig::CONFIG["target_os"] =~ /mingw|mswin/
      require 'win32api'

      def get_short_win32_filename(long_name)
        max_path = 1024
        short_name = " " * max_path
        lfn_size = Win32API.new("kernel32", "GetShortPathName", %w(P P L), 'L').call(long_name, short_name, max_path)
        (1..max_path).include?(lfn_size) ? short_name[0..lfn_size - 1] : long_name
      end

      def get_long_win32_filename(short_name)
        max_path = 1024
        long_name = " " * max_path
        lfn_size = Win32API.new("kernel32", "GetLongPathName", %w(P P L), 'L').call(short_name, long_name, max_path)
        (1..max_path).include?(lfn_size) ? long_name[0..lfn_size - 1] : short_name
      end

      get_long_win32_filename(get_short_win32_filename(name))
    else
      name
    end

  end

  def parse_custom_check_line(compiler, src_path, build_path, line)
    # JSON formatted output is expected here
    begin
      json = JSON.parse(line)
    rescue JSON::ParserError
      return CodeMessage.new('DecentCI::resultsprocessor::parse_custom_check_line', __LINE__, 0, "error", "Output of custom_check script was not formatted properly; should be individual line-by-line JSON objects")
    end

    if json.is_a?(Array)
      return CodeMessage.new('DecentCI::resultsprocessor::parse_custom_check_line', __LINE__, 0, "error", "Output of custom_check script was not formatted properly, it was an array; should be individual line-by-line JSON objects")
    end

    # expected fields to be read: "tool", "file", "line", "column" (optional), "messagetype", "message", "id" (optional)
    if !json["filename"].nil?
      message = json["message"]
      unless json["id"].nil?
        message = "(#{json["id"]}) #{message}"
      end

      unless json["tool"].nil?
        message = "[#{json["tool"]}] #{message}"
      end

      CodeMessage.new(relative_path(json["filename"], src_path, build_path, compiler), json["line"], (json["column"].nil? ? 0 : json["column"]), json["messagetype"], message)
    else
      nil
    end
  end


  def parse_cppcheck_line(compiler, src_path, build_path, line)
    line_number = nil
    message_type = nil
    /\[(?<filename>.*)\]:(?<line_number>[0-9]+):(?<message_type>\S+):(?<message>.*)/ =~ line
    if !filename.nil? && !message_type.nil?
      CodeMessage.new(relative_path(filename, src_path, build_path, compiler), line_number, 0, message_type, message)
    else
      nil
    end
  end

  def parse_regression_line(line)
    /(?<name>\S+);(?<status>\S+);(?<time>\S+);(?<message>.*)/ =~ line
    if !name.nil? && !status.nil?
      TestResult.new("regression.#{name}", status, time, message, nil, status)
    else
      nil
    end
  end

  def process_custom_check_results(compiler, src_dir, build_dir, stdout, stderr, result)
    results = []
    stdout.encode('UTF-8', :invalid => :replace).split("\n").each {|line|
      $logger.debug("Parsing custom_check stdout line: #{line}")
      msg = parse_custom_check_line(compiler, src_dir, build_dir, line)
      unless msg.nil?
        results << msg
      end
    }
    stderr.encode('UTF-8', :invalid => :replace).split("\n").each {|line|
      $logger.debug("Parsing custom_check stderr line: #{line}")
      msg = parse_custom_check_line(compiler, src_dir, build_dir, line)
      unless msg.nil?
        results << msg
      end
    }
    @build_results.merge(results)
    result == 0
  end


  def process_cppcheck_results(compiler, src_dir, build_dir, stderr, result)
    results = []
    stderr.encode('UTF-8', :invalid => :replace).split("\n").each {|line|
      $logger.debug("Parsing cppcheck line: #{line}")
      msg = parse_cppcheck_line(compiler, src_dir, build_dir, line)
      unless msg.nil?
        results << msg
      end
    }
    @build_results.merge(results)
    result == 0
  end

  def process_cmake_results(compiler, src_dir, build_dir, stderr, result, is_package)
    results = []

    file = nil
    line = nil
    msg = ""
    type = nil

    $logger.info("Parsing cmake error results")

    previous_line = ""
    last_was_error_line = false

    stderr.encode('UTF-8', :invalid => :replace).split("\n").each {|err|

      # Append next line to the message context for a CMake error
      if last_was_error_line && !results.empty?
        stripped = err.strip
        if stripped != ""
          last_item = results.last
          last_item.message = last_item.message + "; " + stripped
          results[results.length - 1] = last_item
        end
      end

      last_was_error_line = false

      $logger.debug("Parsing cmake error Line: #{err}")
      if err.strip == ""
        if !file.nil? && !line.nil? && !msg.nil?
          results << CodeMessage.new(relative_path(file, src_dir, build_dir, compiler), line, 0, type, "#{previous_line}#{err}")
          last_was_error_line = true
        end
        file = nil
        line = nil
        msg = ""
        type = nil
      else
        if file.nil?
          /^CPack Error: (?<message>.*)/ =~ err
          unless message.nil?
            results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "error", "#{previous_line}#{err.strip}")
            last_was_error_line = true
          end

          /^CMake Error: (?<message>.*)/ =~ err
          unless message.nil?
            results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "error", "#{previous_line}#{err.strip}")
            last_was_error_line = true
          end

          /^ERROR: (?<message>.*)/ =~ err
          unless message.nil?
            results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "error", "#{previous_line}#{err.strip}")
            last_was_error_line = true
          end

          /^WARNING: (?<message>.*)/ =~ err
          unless message.nil?
            results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "warning", "#{previous_line}#{err.strip}")
            last_was_error_line = true
          end

          message_type = nil
          line_number = nil
          /CMake (?<message_type>\S+) at (?<filename>.*):(?<line_number>[0-9]+) \(\S+\):$/ =~ err

          if !filename.nil? && !line_number.nil?
            file = filename
            line = line_number
            type = message_type.nil? ? "error" : message_type.downcase
          else
            /(?<filename>.*):(?<line_number>[0-9]+):$/ =~ err

            if !filename.nil? && !line_number.nil? && !(filename =~ /file included/i) && !(filename =~ /^\s*from\s+/i)
              file = filename
              line = line_number
              type = "error"
            end
          end

        else
          if msg != ""
            msg << "\n"
          end

          msg << err
        end
      end

      previous_line = err.strip
      if previous_line != ""
        previous_line += "; "
      end
    }

    # get any lingering message from the last line
    if !file.nil? && !line.nil? && !msg.nil?
      results << CodeMessage.new(relative_path(file, src_dir, build_dir, compiler), line, 0, type, msg)
    end

    results.each {|r|
      $logger.debug("CMake error message parsed: #{r.inspect}")
    }

    if is_package
      @package_results.merge(results)
    else
      @build_results.merge(results)
    end

    result == 0
  end

  def parse_generic_line(compiler, src_dir, build_dir, line)
    line_number = nil
    message = nil
    /\s*(?<filename>\S+):(?<line_number>[0-9]+): (?<message>.*)/ =~ line
    if !filename.nil? && !message.nil?
      CodeMessage.new(relative_path(filename, src_dir, build_dir, compiler), line_number, 0, "error", message)
    else
      nil
    end
  end

  def parse_msvc_line(compiler, src_dir, build_dir, line)
    line_number = nil
    message_type = nil
    message_code = nil
    message = nil
    /(?<filename>.+)\((?<line_number>[0-9]+)\): (?<message_type>.+?) (?<message_code>\S+): (?<message>.*) \[.*\]?/ =~ line
    if !filename.nil? && !message_type.nil? && message_type != "info" && message_type != "note"
      CodeMessage.new(relative_path(recover_file_case(filename.strip), src_dir, build_dir, compiler), line_number, 0, message_type, message_code + " " + message)
    else
      /(?<filename>.+) : (?<message_type>\S+) (?<message_code>\S+): (?<message>.*) \[.*\]?/ =~ line
      if !filename.nil? && !message_type.nil? && message_type != "info" && message_type != "note"
        return CodeMessage.new(relative_path(recover_file_case(filename.strip), src_dir, build_dir, compiler), 0, 0, message_type, message_code + " " + message)
      else
        return nil
      end
    end
  end

  def process_msvc_results(compiler, src_dir, build_dir, stdout, result)
    results = []
    stdout.encode('UTF-8', :invalid => :replace).split("\n").each {|err|
      msg = parse_msvc_line(compiler, src_dir, build_dir, err)
      unless msg.nil?
        results << msg
      end
    }
    @build_results.merge(results)
    result == 0
  end

  def parse_gcc_line(compiler, src_path, build_path, line)
    line_number = nil
    column_number = nil
    message_type = nil
    message = nil
    /(?<filename>.*):(?<line_number>[0-9]+):(?<column_number>[0-9]+): (?<message_type>.+?): (?<message>.*)/ =~ line
    if !filename.nil? && !message_type.nil? && message_type != "info" && message_type != "note"
      CodeMessage.new(relative_path(filename, src_path, build_path, compiler), line_number, column_number, message_type, message)
    else
      /(?<filename>.*):(?<line_number>[0-9]+): (?<message>.*)/ =~ line
      # catch linker errors
      if !filename.nil? && !message.nil? && (message =~ /.*multiple definition.*/ || message =~ /.*undefined.*/)
        return CodeMessage.new(relative_path(filename, src_path, build_path, compiler), line_number, 0, "error", message)
      else
        return nil
      end
    end
  end

  def process_gcc_results(compiler, src_path, build_path, stderr, result)
    results = []
    linker_msg = nil

    stderr.encode('UTF-8', :invalid => :replace).split("\n").each {|line|
      unless linker_msg.nil?
        if line =~ /^\s.*/
          linker_msg += "\n" + line
        else
          results << CodeMessage.new("CMakeLists.txt", 0, 0, "error", linker_msg)
          linker_msg = nil
        end
      end

      msg = parse_gcc_line(compiler, src_path, build_path, line)
      if !msg.nil?
        results << msg
      else
        # try to catch some goofy clang linker errors that don't give us very much info
        if /^Undefined symbols for architecture.*/ =~ line
          linker_msg = line
        end
      end
    }

    unless linker_msg.nil?
      results << CodeMessage.new("CMakeLists.txt", 0, 0, "error", linker_msg)
    end

    @build_results.merge(results)

    result == 0
  end

  def parse_error_messages(compiler, src_dir, build_dir, output)
    results = []
    output.encode('UTF-8', :invalid => :replace).split("\n").each {|l|
      msg = parse_gcc_line(compiler, src_dir, build_dir, l)
      msg = parse_msvc_line(compiler, src_dir, build_dir, l) if msg.nil?
      msg = parse_generic_line(compiler, src_dir, build_dir, l) if msg.nil?
      results << msg unless msg.nil?
    }
    results
  end

  def parse_python_or_latex_line(compiler, src_dir, build_dir, line)
    line_number = nil
    # Since we are just doing line-by-line parsing, it really limits what we can get, but we'll try our best anyway
    if 'LaTeX Error'.include?(line)
      # Example LaTeX Error (third line):
      # LaTeX Font Info: Checking defaults for U/cmr/m/n on input line 3.
      # LaTeX Font Info: ... okay on input line 3.
      # ! LaTeX Error: Environment itemize undefined.
      # See the LaTeX manual or LaTeX Companion for explanation.
      # Type H <return> for immediate help.
      /^.*Error: (?<message>.+)/ =~ line
      compiler_string = 'LaTeX'
    else
      # assume Python
      # Example Python Error (last line)
      # Traceback (most recent call last):
      #   File "/tmp/python_error.py", line 1, in <module>
      #     print('c' + 3)
      # TypeError: cannot concatenate 'str' and 'int' objects
      /File "(?<filename>.+)", line (?<line_number>[0-9]+),.*/ =~ line
      /^.*Error: (?<message>.+)/ =~ line
      compiler_string = 'Python'
    end

    $logger.debug("Parsing line for python/LaTeX errors: #{line}: #{filename} #{line_number} #{message}")

    if !filename.nil? && !line_number.nil?
      CodeMessage.new(relative_path(filename.strip, src_dir, build_dir, compiler), line_number, 0, "error", "Error")
    elsif !message.nil?
      return CodeMessage.new(relative_path(compiler_string, src_dir, build_dir, compiler), 0, 0, "error", message)
    end

  end

  def process_python_results(compiler, src_dir, build_dir, stdout, stderr, result)
    results = []
    stdout.encode('UTF-8', :invalid => :replace).split("\n").each {|err|
      msg = parse_python_or_latex_line(compiler, src_dir, build_dir, err)
      unless msg.nil?
        results << msg
      end
    }
    $logger.debug("stdout results: #{results}")
    @build_results.merge(results)
    results = []
    stderr.encode('UTF-8', :invalid => :replace).split("\n").each {|err|
      msg = parse_python_or_latex_line(compiler, src_dir, build_dir, err)
      unless msg.nil?
        results << msg
      end
    }
    $logger.debug("stderr results: #{results}")
    @build_results.merge(results)
    result == 0
  end

  def parse_package_names(output)
    results = []
    output.encode('UTF-8', :invalid => :replace).split("\n").each {|l|
      /CPack: - package: (?<filename>.*) generated./ =~ l
      results << filename if filename
    }
    results
  end

  def process_lcov_results(out)
    #Overall coverage rate:
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

    out.encode('UTF-8', :invalid => :replace).split("\n").each {|l|
      /.*\((?<covered_lines_str>[0-9]+) of (?<total_lines_str>[0-9]+) lines.*/ =~ l
      covered_lines = covered_lines_str.to_i unless covered_lines_str.nil?
      total_lines = total_lines_str.to_i unless total_lines_str.nil?

      /.*\((?<covered_functions_str>[0-9]+) of (?<total_functions_str>[0-9]+) functions.*/ =~ l
      covered_functions = covered_functions_str.to_i unless covered_functions_str.nil?
      total_functions = total_functions_str.to_i unless total_functions_str.nil?
    }

    [total_lines, covered_lines, total_functions, covered_functions]
  end

  def process_ctest_results(compiler, src_dir, build_dir, test_dir)
    unless File.directory?(test_dir)
      $logger.error("Error: test_dir #{test_dir} does not exist, cannot parse test results")
      return nil, []
    end

    messages = []

    Find.find(test_dir) do |path|
      if path =~ /.*Test.xml/
        results = []

        xml = Hash.from_xml(File.open(path).read)
        test_results = xml["Site"]["Testing"]
        t = test_results["Test"]
        unless t.nil?
          tests = []
          tests << t
          tests.flatten!

          tests.each {|n|
            $logger.debug("N: #{n}")
            $logger.debug("Results: #{n["Results"]}")
            r = n["Results"]
            if n["Status"] == "notrun"
              results << TestResult.new(n["Name"], n["Status"], 0, "", nil, "notrun")
            else
              if r
                m = r["Measurement"]
                value = nil
                errors = nil

                unless m.nil?
                  value = m["Value"]
                  unless value.nil?
                    errors = parse_error_messages(compiler, src_dir, build_dir, value)

                    value.split("\n").each {|line|
                      if /\[decent_ci:test_result:message\] (?<message>.+)/ =~ line
                        messages << TestMessage.new(n["Name"], message);
                      end

                    }
                  end
                end


                nm = r["NamedMeasurement"]

                unless nm.nil?
                  failure_type = ""
                  nm.each {|measurement|
                    if measurement["name"] == "Exit Code"
                      ft = measurement["Value"]
                      unless ft.nil?
                        failure_type = ft
                      end
                    end
                  }

                  nm.each {|measurement|
                    if measurement["name"] == "Execution Time"
                      status_string = n["Status"]
                      if !value.nil? && value =~ /\[decent_ci:test_result:warn\]/ && status_string == "passed"
                        status_string = "warning"
                      end
                      results << TestResult.new(n["Name"], status_string, measurement["Value"], value, errors, failure_type)
                    end
                  }
                end

              end
            end
          }
        end

        if results.empty?
          return nil, messages
        else
          return results, messages
        end
      end

    end
  end
end

