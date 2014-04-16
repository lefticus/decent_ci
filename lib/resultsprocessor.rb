# encoding: UTF-8 
module ResultsProcessor
  def relative_path(p, src_dir, build_dir, compiler)
    begin
      return Pathname.new("#{src_dir}/#{p}").realpath.relative_path_from(Pathname.new(build_base_name compiler).realdirpath)
    rescue
      begin
        return Pathname.new("#{build_dir}/#{p}").realpath.relative_path_from(Pathname.new(build_base_name compiler).realdirpath)
      rescue
        begin 
          return Pathname.new(p).realpath.relative_path_from(Pathname.new(build_base_name compiler).realdirpath)
        rescue
          return Pathname.new(p)
        end
      end
    end
  end

  def process_cmake_results(compiler, src_dir, build_dir, stdout, stderr, result, is_package)
    results = []

    file = nil
    line = nil
    msg = ""
    type = nil

    @logger.info("Parsing cmake error results")

    stderr.split("\n").each{ |err|

      @logger.debug("Parsing cmake error Line: #{err}")
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

          /CMake (?<messagetype>\S+) at (?<filename>.*):(?<linenumber>[0-9]+) \(\S+\):$/ =~ err

          if !filename.nil? && !linenumber.nil?
            file = filename
            line = linenumber
            type = messagetype.downcase
          else
            /(?<filename>.*):(?<linenumber>[0-9]+):$/ =~ err

            if !filename.nil? && !linenumber.nil?
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
      @logger.debug("CMake error message parsed: #{r.inspect}")
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
    /\s+(?<filename>\S+)\((?<linenumber>[0-9]+)\): (?<messagetype>\S+) (?<messagecode>\S+): (?<message>.*) \[.*\]/ =~ line

    if !filename.nil? && !messagetype.nil? && messagetype != "info" && messagetype != "note"
      return CodeMessage.new(relative_path(filename, src_dir, build_dir, compiler), linenumber, 0, messagetype, message)
    else
      return nil
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
    /(?<filename>\S+):(?<linenumber>[0-9]+):(?<colnumber>[0-9]+): (?<messagetype>\S+): (?<message>.*)/ =~ line

    if !filename.nil? && !messagetype.nil? && messagetype != "info" && messagetype != "note"
      return CodeMessage.new(relative_path(filename, src_path, build_path, compiler), linenumber, colnumber, messagetype, message)
    else
      return nil
    end

  end

  def process_gcc_results(compiler, src_path, build_path, stdout, stderr, result)
    results = []

    stderr.split("\n").each { |line|
      msg = parse_gcc_line(compiler, src_path, build_path, line)
      if !msg.nil?
        results << msg
      end
    }

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



  def process_ctest_results compiler, src_dir, build_dir, stdout, stderr, result
    Find.find(build_dir) do |path|
      if path =~ /.*Test.xml/
        results = []

        xml = Hash.from_xml(File.open(path).read)
        testresults = xml["Site"]["Testing"]
        testresults.each { |t, n|
          if t == "Test"
            r = n["Results"]
            if n["Status"] == "notrun"
              results << TestResult.new(n["Name"], n["Status"], 0)
            else
              if r
                m = r["Measurement"]
                value = nil
                errors = nil

                if !m.nil?
                  value = m["Value"]
                  if !value.nil?
                    errors = parse_error_messages(compiler, src_dir, build_dir, value)
                  end
                end

                nm = r["NamedMeasurement"]

                if !nm.nil?
                  nm.each { |measurement|
                    if measurement["name"] == "Execution Time"
                      results << TestResult.new(n["Name"], n["Status"], measurement["Value"], value, errors);
                    end
                  }
                end

              end
            end
          end
        }

        return results
      end

    end
  end
end
