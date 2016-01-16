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
        lfn_size = Win32API.new("kernel32",
                                "GetShortPathName", ['P','P','L'],'L').call(long_name, short_name, max_path)
        return (1..max_path).include?(lfn_size) ? short_name[0..lfn_size-1] : long_name
      end

      def get_long_win32_filename(short_name)
        max_path = 1024
        long_name = " " * max_path
        lfn_size = Win32API.new("kernel32",
                                "GetLongPathName", ['P','P','L'],'L').call(short_name, long_name, max_path)
        return (1..max_path).include?(lfn_size) ? long_name[0..lfn_size-1] : short_name
      end
      return get_long_win32_filename(get_short_win32_filename(name))
    else
      return name
    end

  end

  def parse_cppcheck_line(compiler, src_path, build_path, line)
    /\[(?<filename>.*)\]:(?<linenumber>[0-9]+):(?<messagetype>\S+):(?<message>.*)/ =~ line

    if !filename.nil? && !messagetype.nil?
      return CodeMessage.new(relative_path(filename, src_path, build_path, compiler), linenumber, 0, messagetype, message)
    else
      return nil
    end
  end

  def parse_regression_line(line)
    /(?<name>\S+);(?<status>\S+);(?<time>\S+);(?<message>.*)/ =~ line

    if !name.nil? && !status.nil?
      return TestResult.new("regression.#{name}", status, time, message, nil)
    else
      return nil
    end
  end

  def process_regression_results(stdout, stderr, result)
    results = []

    stdout.split("\n").each { |line|
      $logger.debug("Parsing regression line: #{line}")
      msg = parse_regression_line(line)
      if !msg.nil?
        results << msg
      end
    }

    return results
  end



  def process_cppcheck_results(compiler, src_dir, build_dir, stdout, stderr, result)
    results = []

    stderr.split("\n").each { |line|
      $logger.debug("Parsing cppcheck line: #{line}")
      msg = parse_cppcheck_line(compiler, src_dir, build_dir, line)
      if !msg.nil?
        results << msg
      end
    }

    @build_results.merge(results)

    return result == 0
  end

  def process_cmake_results(compiler, src_dir, build_dir, stdout, stderr, result, is_package)
    results = []

    file = nil
    line = nil
    msg = ""
    type = nil

    $logger.info("Parsing cmake error results")

    stderr.split("\n").each{ |err|

      $logger.debug("Parsing cmake error Line: #{err}")
      if err.strip == ""
        if !file.nil? && !line.nil? && !msg.nil?
          results << CodeMessage.new(relative_path(file, src_dir, build_dir, compiler), line, 0, type, msg)
        end
        file = nil
        line = nil
        msg = "" 
        type = nil
      else
        if file.nil? 
          /^CPack Error: (?<message>.*)/ =~ err
          results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "error", message) if !message.nil?

          /^CMake Error: (?<message>.*)/ =~ err
          results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "error", message) if !message.nil?

          /^ERROR: (?<message>.*)/ =~ err
          results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "error", message) if !message.nil?

          /^WARNING: (?<message>.*)/ =~ err
          results << CodeMessage.new(relative_path("CMakeLists.txt", src_dir, build_dir, compiler), 1, 0, "warning", message) if !message.nil?


          /CMake (?<messagetype>\S+) at (?<filename>.*):(?<linenumber>[0-9]+) \(\S+\):$/ =~ err

          if !filename.nil? && !linenumber.nil?
            file = filename
            line = linenumber
            type = messagetype.downcase
          else
            /(?<filename>.*):(?<linenumber>[0-9]+):$/ =~ err

            if !filename.nil? && !linenumber.nil? && !(filename =~ /file included/i) && !(filename =~ /^\s*from\s+/i)
              file = filename
              line = linenumber
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
    }

    # get any lingering message from the last line
    if !file.nil? && !line.nil? && !msg.nil?
      results << CodeMessage.new(relative_path(file, src_dir, build_dir, compiler), line, 0, type, msg)
    end

    results.each { |r| 
      $logger.debug("CMake error message parsed: #{r.inspect}")
    }

    if is_package
      @package_results.merge(results)
    else
      @build_results.merge(results)
    end

    return result == 0
  end

  def parse_generic_line(compiler, src_dir, build_dir, line)
    /\s*(?<filename>\S+):(?<linenumber>[0-9]+): (?<message>.*)/ =~ line

    if !filename.nil? && !message.nil?
      return CodeMessage.new(relative_path(filename, src_dir, build_dir, compiler), linenumber, 0, "error", message)
    else
      return nil
    end
  end

  def parse_msvc_line(compiler, src_dir, build_dir, line)
    /(?<filename>.+)\((?<linenumber>[0-9]+)\): (?<messagetype>.+?) (?<messagecode>\S+): (?<message>.*) \[.*\]?/ =~ line

    if !filename.nil? && !messagetype.nil? && messagetype != "info" && messagetype != "note"
      return CodeMessage.new(relative_path(recover_file_case(filename.strip), src_dir, build_dir, compiler), linenumber, 0, messagetype, messagecode + " " + message)
    else
      /(?<filename>.+) : (?<messagetype>\S+) (?<messagecode>\S+): (?<message>.*) \[.*\]?/ =~ line

      if !filename.nil? && !messagetype.nil? && messagetype != "info" && messagetype != "note"
        return CodeMessage.new(relative_path(recover_file_case(filename.strip), src_dir, build_dir, compiler), 0, 0, messagetype, messagecode + " " + message)
      else
        return nil
      end
    end
  end

  def process_msvc_results(compiler, src_dir, build_dir, stdout, stderr, result)
    results = []
    stdout.split("\n").each{ |err|
      msg = parse_msvc_line(compiler, src_dir, build_dir, err)
      if !msg.nil?
        results << msg
      end
    }

    @build_results.merge(results)

    return result == 0 
  end

  def parse_gcc_line(compiler, src_path, build_path, line)
    /(?<filename>.*):(?<linenumber>[0-9]+):(?<colnumber>[0-9]+): (?<messagetype>.+?): (?<message>.*)/ =~ line

    if !filename.nil? && !messagetype.nil? && messagetype != "info" && messagetype != "note"
      return CodeMessage.new(relative_path(filename, src_path, build_path, compiler), linenumber, colnumber, messagetype, message)
    else
      /(?<filename>.*):(?<linenumber>[0-9]+): (?<message>.*)/ =~ line

      # catch linker errors
      if !filename.nil? && !message.nil? && (message =~ /.*multiple definition.*/ || message =~ /.*undefined.*/)
        return CodeMessage.new(relative_path(filename, src_path, build_path, compiler), linenumber, 0, "error", message)
      else
        return nil
      end
    end

  end

  def process_gcc_results(compiler, src_path, build_path, stdout, stderr, result)
    results = []
    linkerrmsg = nil

    stderr.split("\n").each { |line|
      if !linkerrmsg.nil?
        if line =~ /^\s.*/
          linkerrmsg += "\n" + line
        else
          results << CodeMessage.new("CMakeLists.txt", 0, 0, "error", linkerrmsg)
          linkerrmsg = nil
        end
      end

      msg = parse_gcc_line(compiler, src_path, build_path, line)
      if !msg.nil?
        results << msg
      else 
        # try to catch some goofy clang linker errors that don't give us very much info
        if /^Undefined symbols for architecture.*/ =~ line
          linkerrmsg = line
        end
      end
    }

    if !linkerrmsg.nil?
      results << CodeMessage.new("CMakeLists.txt", 0, 0, "error", linkerrmsg)
    end

    @build_results.merge(results)

    return result == 0
  end

  def parse_error_messages compiler, src_dir, build_dir, output
    results = []
    output.split("\n").each{ |l|
      msg = parse_gcc_line(compiler, src_dir, build_dir, l)
      msg = parse_msvc_line(compiler, src_dir, build_dir, l) if msg.nil?
      msg = parse_generic_line(compiler, src_dir, build_dir, l) if msg.nil?

      results << msg if !msg.nil?
    }

    return results
  end

  def parse_python_line(compiler, src_dir, build_dir, line)
    /File "(?<filename>.+)", line (?<linenumber>[0-9]+),.*/ =~ line
    /^.*Error: (?<message>.+)/ =~ line

    $logger.debug("Parsing line for python errors: #{line}: #{filename} #{linenumber} #{message}")

    if !filename.nil? && !linenumber.nil?
      return CodeMessage.new(relative_path(filename.strip, src_dir, build_dir, compiler), linenumber, 0, "error", "Error")
    elsif !message.nil?
      return CodeMessage.new(relative_path("python", src_dir, build_dir, compiler), 0, 0, "error", message)
    end

  end

  def process_python_results(compiler, src_dir, build_dir, stdout, stderr, result)
    results = []
    stdout.split("\n").each{ |err|
      msg = parse_python_line(compiler, src_dir, build_dir, err)
      if !msg.nil?
        results << msg
      end
    }
    $logger.debug("stdout results: #{results}")
    @build_results.merge(results)
    results = []
    stderr.split("\n").each{ |err|
      msg = parse_python_line(compiler, src_dir, build_dir, err)
      if !msg.nil?
        results << msg
      end
    }


    $logger.debug("stderr results: #{results}")
    @build_results.merge(results)

    return result == 0 
  end

  def parse_package_names(output)
    results = []
    output.split("\n").each { |l| 
      /CPack: - package: (?<filename>.*) generated./ =~ l
      results << filename if filename
    }

    return results
  end

  def process_lcov_results(compiler, src_dir, build_dir, out, err, result)
    #Overall coverage rate:
    #  lines......: 67.9% (173188 of 255018 lines)
    #  functions..: 83.8% (6228 of 7433 functions)

    total_lines = 0
    covered_lines = 0
    total_functions = 0
    covered_functions = 0

    out.split("\n").each{ |l|
      /.*\((?<covered_lines_str>[0-9]+) of (?<total_lines_str>[0-9]+) lines.*/ =~ l
      covered_lines = covered_lines_str.to_i if !covered_lines_str.nil?
      total_lines = total_lines_str.to_i if !total_lines_str.nil?

      /.*\((?<covered_functions_str>[0-9]+) of (?<total_functions_str>[0-9]+) functions.*/ =~ l
      covered_functions = covered_functions_str.to_i if !covered_functions_str.nil?
      total_functions = total_functions_str.to_i if !total_functions_str.nil?
    }

    return [total_lines, covered_lines, total_functions, covered_functions]
  end

  def process_ctest_results compiler, src_dir, build_dir, test_dir, stdout, stderr, result
    if !File.directory?(test_dir)
      $logger.error("Error: test_dir #{test_dir} does not exist, cannot parse test results")
      return nil, []
    end

    messages = []

    Find.find(test_dir) do |path|
      if path =~ /.*Test.xml/
        results = []

        xml = Hash.from_xml(File.open(path).read)
        testresults = xml["Site"]["Testing"]
        t = testresults["Test"]
        if !t.nil? 
          tests = []
          tests << t
          tests.flatten!

          tests.each { |n|
            $logger.debug("N: #{n}")
            $logger.debug("Results: #{n["Results"]}")
            r = n["Results"]
            if n["Status"] == "notrun"
              results << TestResult.new(n["Name"], n["Status"], 0, "", nil)
            else
              if r
                m = r["Measurement"]
                value = nil
                errors = nil

                if !m.nil?
                  value = m["Value"]
                  if !value.nil?
                    errors = parse_error_messages(compiler, src_dir, build_dir, value)

                    value.split("\n").each { |line|
                      if /\[decent_ci:test_result:message\] (?<message>.+)/ =~ line
                        messages << TestMessage.new(n["Name"], message);
                      end

                    }
                  end
                end


                nm = r["NamedMeasurement"]

                if !nm.nil?
                  nm.each { |measurement|
                    if measurement["name"] == "Execution Time"
                      status_string = n["Status"]
                      if !value.nil? && value =~ /\[decent_ci:test_result:warn\]/ && status_string == "passed"
                        status_string = "warning" 
                      end
                      results << TestResult.new(n["Name"], status_string, measurement["Value"], value, errors);
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

