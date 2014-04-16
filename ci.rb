# encoding: UTF-8 

require 'octokit'
require 'json'
require 'open3'
require 'pathname'
require 'active_support/core_ext/hash'
require 'find'
require 'logger'
require 'fileutils'
require 'ostruct'
require 'yaml'
require 'base64'

class CodeMessage
  include Comparable
  attr_reader :filename
  attr_reader :linenumber
  attr_reader :colnumber
  attr_reader :messagetype
  attr_reader :message

  def initialize(filename, linenumber, colnumber, messagetype, message)
    @filename = filename
    @linenumber = linenumber
    @colnumber = colnumber
    @messagetype = messagetype
    @message = message
  end

  def is_warning
    @messagetype =~ /.*warn.*/i
  end

  def is_error
    @messagetype =~ /.*err.*/i
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

  def hash 
    return inspect.hash
  end

  def eql?(other)
    return (self <=> other) == 0
  end

  def <=> (other)
    f = @filename <=> other.filename
    l = @linenumber.to_i <=> other.linenumber.to_i
    c = @colnumber.to_i <=> other.colnumber.to_i
    mt = @messagetype <=> other.messagetype
    m = @message <=> other.message

    if f != 0 
      return f
    elsif l != 0
      return l
    elsif c != 0
      return c
    elsif mt != 0
      return mt
    else
      return m
    end

  end

end

class TestResult
  def initialize(name, status, time, output, parsed_errors)
    @name = name
    @status = status
    @time = time
    @output = output
    @parsed_errors = parsed_errors
  end

  def passed
    return @status == "passed"
  end

  def inspect
    parsed_errors_array = []

    if !@parsed_errors.nil?
      @parsed_errors.each { |e|
        parsed_errors_array << e.inspect
      }
    end

    hash = {:name => @name,
      :status => @status,
      :time => @time,
      :output => @output,
      :parsed_errors => parsed_errors_array
      }
    return hash
  end

end

class PotentialBuild

  def initialize(client, token, repository, tag_name, commit_sha, branch_name, release_url, release_assets, 
                 pull_id, pull_request_base_repository, pull_request_base_ref)
    @logger = Logger.new(STDOUT)
    @client = client
    @config = load_configuration(repository, (tag_name.nil? ? commit_sha : tag_name))
    @config.repository_name = @client.repo(repository).name
    @config.repository = repository
    @repository = repository
    @tag_name = tag_name
    @commit_sha = commit_sha
    @branch_name = branch_name
    @release_url = release_url
    @release_assets = release_assets

    @buildid = @tag_name ? @tag_name : @commit_sha
    @refspec = @tag_name ? @tag_name : @branch_name

    @pull_id = pull_id
    @pull_request_base_repository = pull_request_base_repository
    @pull_request_base_ref = pull_request_base_ref


    @buildid = "#{@buildid}-PR#{@pull_id}" if !@pull_id.nil?

    @created_dirs = []
    @package_location = nil
    @test_results = nil
    @build_results = SortedSet.new()
    @package_results = SortedSet.new()
    @dateprefix = nil
    @failure = nil
    @test_run = false
  end

  def compilers
    return @config.compilers
  end

  # Cross-platform way of finding an executable in the $PATH.
  #
  #   which('ruby') #=> /usr/bin/ruby
  def which(cmd, extra_paths=nil)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    path_array = ENV['PATH'].split(File::PATH_SEPARATOR)
    if !extra_paths.nil?
      path_array = path_array.concat(extra_paths)
    end

    path_array.each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return Pathname.new(exe).realpath.to_s if File.executable? exe
      }
    end
    return nil
  end

  def load_configuration(location, ref)
    def load_yaml(name, location, ref)

      if !location.nil? && !name.nil?
        begin
          content = @client.content(location, {:path=>name, :ref=>ref} )
          contents = content.content
          return YAML.load(Base64.decode64(contents.to_s))

        rescue => e
          @logger.info("Unable to load yaml file from repository: #{location}/#{name}@#{ref} error: #{e} #{e.backtrace}")

          path = File.expand_path(name, location)
          @logger.info("Attempting to load yaml config file: #{path}")
          if File.exists?(path)
            return YAML.load_file(path)
          else
            @logger.info("yaml file does not exist: #{path}")
            return nil
          end
        end
      else
        return nil
      end
    end

    def symbolize(obj)
      return obj.reduce({}) do |memo, (k, v)|
        memo.tap { |m| m[k.to_sym] = symbolize(v) }
      end if obj.is_a? Hash

      return obj.reduce([]) do |memo, v| 
        memo << symbolize(v); memo
      end if obj.is_a? Array

      obj
    end

    if RUBY_PLATFORM  =~ /darwin/i
      os_distribution = nil
      os_version = "MacOS"
      ver_string = `uname -v`.strip

      /.* Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\.(?<ver_patch>[0-9]+).*:.*/ =~ ver_string
      # the darwin version number - 4 = the point release of macosx
      os_release = "10.#{ver_major.to_i - 4}"

    elsif RUBY_PLATFORM =~ /linux/i
      os_distribution = `lsb_release -is`.strip
      os_version = "Linux"
      os_release = "#{`lsb_release -is`.strip}-#{`lsb_release -rs`.strip}"
    else
      os_distribution = nil
      os_version = "Windows"
      ver_string = `cmd /c ver`.strip

      /.* \[Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\..*\]/ =~ ver_string

      os_release = nil

      case ver_major.to_i
      when 5
        case ver_minor.to_i
        when 0
          os_release = "2000"
        when 1
          os_release = "XP"
        when 2
          os_release = "2003"
        end
      when 6
        case ver_minor.to_i
        when 0
          os_release = "Vista"
        when 1
          os_release = "7"
        when 2
          os_release = "8"
        when 3
          os_release = "8.1"
        end
      end


      if os_release.nil?
        os_release = "Unknown-#{ver_major}.#{ver_minor}"
      end
    end

    yaml_base_name = ".ci"
    yaml_name = "#{yaml_base_name}.yaml"
    yaml_os_name = "#{yaml_base_name}-#{os_version}.yaml"
    yaml_os_distribution_name = nil

    if !os_distribution.nil?
      yaml_os_distribution_name = "#{yaml_base_name}-#{os_version}-#{os_distribution}.yaml"
    end

    yaml_os_release_name = "#{yaml_base_name}-#{os_version}-#{os_release}.yaml"

    base_yaml = load_yaml(yaml_name, location, ref)
    @logger.debug("Base yaml loaded: #{base_yaml}") if !base_yaml.nil?
    os_yaml = load_yaml(yaml_os_name, location, ref)
    @logger.debug("os yaml loaded: #{os_yaml}") if !os_yaml.nil?
    os_distribution_yaml = load_yaml(yaml_os_distribution_name, location, ref)
    @logger.debug("os distribution yaml loaded: #{os_distribution_yaml}") if !os_distribution_yaml.nil?
    os_distribution_release_yaml = load_yaml(yaml_os_release_name, location, ref)
    @logger.debug("os distribution release yaml loaded: #{os_distribution_release_yaml}") if !os_distribution_release_yaml.nil?

    cmake_paths = ["C:\\Program Files\\CMake 2.8\\bin",
                   "C:\\Program Files (x86)\\CMake 2.8\\bin"]

    result_yaml = {
      :os => os_version,
      :os_release => os_release,
      :engine => "cmake",
      :post_results_comment => true,
      :post_results_status => true,
      :post_release_package => true,
      :cmake_bin => "\"#{which("cmake", cmake_paths)}\"",
      :ctest_bin => "\"#{which("ctest", cmake_paths)}\"",
      :cpack_bin => "\"#{which("cpack", cmake_paths)}\""
    }

    result_yaml.merge!(base_yaml) if !base_yaml.nil?
    result_yaml.merge!(os_yaml) if !os_yaml.nil?
    result_yaml.merge!(os_distribution_yaml) if !os_distribution_yaml.nil?
    result_yaml.merge!(os_distribution_release_yaml) if !os_distribution_release_yaml.nil?

    result_yaml = symbolize(result_yaml)

    @logger.info("Final merged configuration: #{result_yaml}")


    configuration = OpenStruct.new(result_yaml)

    raise "No compilers defined" if configuration.compilers.nil?

    # go through the list of compilers specified and fill in reasonable defaults
    # if there are not any specified already
    configuration.compilers.each { |compiler|

      @logger.debug("Working on compiler: #{compiler[:name]}")
      if compiler[:architecture].nil? || compiler[:architecture] == ""
        if compiler[:name] == "Visual Studio"
          compiler[:architecture_description] = "i386"
        else
          compiler[:architecture_description] = RbConfig::CONFIG["host_cpu"]
        end
      else
        compiler[:architecture_description] = compiler[:architecture]
      end

      if compiler[:version].nil?
        case compiler[:name]
        when "Visual Studio"
          raise "Version number for visual studio must be provided"
        when "clang"
          /.*clang version (?<version>([0-9]+\.?)+).*/ =~ `clang --version`
          compiler[:version] = version
        when "gcc"
          compiler[:version] = `gcc -dumpversion`
        end
      end

      if compiler[:name] != "Visual Studio" && (compiler[:cc_bin].nil? || compiler[:cxx_bin].nil?)
        case compiler[:name]
        when "clang"
          potential_name = which("clang-#{compiler[:version]}")
          if !potential_name.nil?
            compiler[:cc_bin] = potential_name
            compiler[:cxx_bin] = which("clang++-#{compiler[:version]}")
          else
            compiler[:cc_bin] = which("clang")
            compiler[:cxx_bin] = which("clang++")
          end
        when "gcc"
          potential_name = which("gcc-#{compiler[:version]}")
          if !potential_name.nil?
            compiler[:cc_bin] = potential_name
            compiler[:cxx_bin] = which("g++-#{compiler[:version]}")
          else
            compiler[:cc_bin] = which("gcc")
            compiler[:cxx_bin] = which("g++")
          end
        end

        if compiler[:cc_bin].nil? || compiler[:cxx_bin].nil?  || !(`#{compiler[:cc_bin]} --version` =~ /.*#{compiler[:version]}/) || !(`#{compiler[:cxx_bin]} --version` =~ /.*#{compiler[:version]}/)

          raise "Unable to find appropriate compiler for: #{compiler[:name]} version #{compiler[:version]}"
        end
      end



      description = compiler[:name].gsub(/\s+/, "")

      if !compiler[:version].nil? && compiler[:version] != ""
        description = "#{description}-#{compiler[:version]}"
      end

      compiler[:description] = description

      if compiler[:build_package_generator].nil? || compiler[:build_package_generator] == ""
        case configuration.os
        when "Windows"
          compiler[:build_package_generator] = "NSIS"
        when "Linux"
          if configuration.os_release =~ /.*ubuntu.*/i || configuration.os_release =~ /.*deb.*/i || configuration.os_release =~ /.*mint.*/i
            compiler[:build_package_generator] = "DEB"
          else
            compiler[:build_package_generator] = "RPM"
          end
        when "MacOS"
          compiler[:build_package_generator] = "PackageMaker"
        end
      end

      if compiler[:build_generator].nil? || compiler[:build_generator] == ""
        case compiler[:name]
        when /.*Visual Studio.*/i
          generator = "Visual Studio #{compiler[:version]}"
          if compiler[:architecture] =~ /.*64.*/
            generator = "#{generator} Win64"
          end
          compiler[:build_generator] = generator
        else
          compiler[:build_generator] = "Unix Makefiles"
        end
      end

      if compiler[:package_extension].nil? || compiler[:package_extension] == ""
        case compiler[:build_package_generator]
        when /.*NSIS.*/
          compiler[:package_extension] = "exe"
        when /.*PackageMaker.*/
          compiler[:package_extension] = "dmg"
        when /T.*/
          /T(?<tar_type>[0-9]+)/ =~ compiler[:build_package_generator]
          compiler[:package_extension] = "tar.#{tar_type.downcase}"
        else
          compiler[:package_extension] = compiler[:build_package_generator].downcase
        end
      end

      case compiler[:package_extension]
      when "deb"
        compiler[:package_mimetype] = "application/x-deb"
      else
        compiler[:package_mimetype] = "application/octet-stream"
      end
    }

    return configuration
  end


  def set_test_run new_test_run
    @test_run = new_test_run
  end

  def descriptive_string
    return "#{@commit_sha} #{@branch_name} #{@tag_name} #{@buildid}"
  end

  def is_release
    return !@release_url.nil?
  end

  def is_pull_request
    return !@pull_id.nil?
  end

  def pull_request_issue_id
    return @pull_id
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
  def run_with_timeout(command, timeout=60*60*4, tick=2)
    out = ""
    err = ""
    begin
      # Start task in another thread, which spawns a process
      stdin, stdout, stderr, thread = Open3.popen3(command)
      # Get the pid of the spawned process
      pid = thread[:pid]
      start = Time.now

      while (Time.now - start) < timeout and thread.alive?
        # Wait up to `tick` seconds for output/error data
        rs, = Kernel.select([stdout, stderr], nil, nil, tick)
        # Try to read the data
        begin
          rs.each { |r|
            if r == stdout
              out << stdout.read_nonblock(4096)
            elsif r == stderr 
              err << stderr.read_nonblock(4096)
            end
          }

        rescue IO::WaitReadable
          # A read would block, so loop around for another select
        rescue EOFError
          # Command has completed, not really an error...
          break
        end
      end
      # Give Ruby time to clean up the other thread
      sleep 1

      if thread.alive?
        # We need to kill the process, because killing the thread leaves
        # the process alive but detached, annoyingly enough.
        Process.kill("TERM", pid)
      end
    ensure
      stdin.close if stdin
      stdout.close if stdout
      stderr.close if stderr
    end
    return out.force_encoding("UTF-8"), err.force_encoding("UTF-8"), thread.value
  end

  def run_script(commands)
    allout = ""
    allerr = "" 
    allresult = 0

    commands.each { |cmd|
      if @config.os == "Windows"
        @logger.warn "Unable to set timeout for process execution on windows"
        stdout, stderr, result = Open3::capture3(cmd)
      else
        stdout, stderr, result = run_with_timeout(cmd)
      end

      stdout.split("\n").each { |l| 
        @logger.debug("cmd: #{cmd}: stdout: #{l}")
      }

      stderr.split("\n").each { |l| 
        @logger.info("cmd: #{cmd}: stderr: #{l}")
      }

      if cmd != commands.last && result != 0
        @logger.error("Error running script command: #{stderr}")
        raise stderr
      end

      allout += stdout
      allerr += stderr
      allresult += result.exitstatus
    }

    return allout, allerr, allresult
  end

  def device_id compiler
    "#{compiler[:architecture_description]}-#{@config.os}-#{@config.os_release}-#{compiler[:description]}"
  end

  def build_base_name compiler
    "#{@config.repository_name}-#{@buildid}-#{device_id(compiler)}"
  end

  def results_file_name compiler
    "#{build_base_name compiler}-results.html"
  end

  def short_build_base_name compiler
    "#{@config.repository_name}-#{compiler[:architecture_description]}-#{@config.os}-#{@buildid}"
  end


  def package_name compiler
    "#{short_build_base_name(compiler)}"
  end


  def package_full_name compiler
    "#{short_build_base_name compiler}.#{compiler[:package_extension]}"
  end

  def needs_release_package compiler
    if @release_assets.nil?
      return true
    end

    @release_assets.each { |f|
      if f.name == package_full_name(compiler)
        return false
      end
    }
    return true
  end

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

  def checkout(src_dir)
    # TODO update this to be a merge, not just a checkout of the pull request branch
    FileUtils.mkdir_p src_dir

    if @config.pull_id.nil?
      out, err, result = run_script(
        ["cd #{src_dir} && git init",
         "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} #{@refspec}" ])

      if !@commit_sha.nil? && @commit_sha != "" && result == 0
        out, err, result = run_script( ["cd #{src_dir} && git checkout #{@commit_sha}"] );
      end
    else 
      out, err, result = run_script(
        ["cd #{src_dir} && git init",
         "cd #{src_dir} && git pull https://#{@config.token}@github.com/#{@repository} refs/pull/#{@config.pull_id}/head",
         "cd #{src_dir} && git checkout FETCH_HEAD" ])
    end

    return result == 0

  end


  def cmake_build(compiler, src_dir, build_dir, build_type)
    FileUtils.mkdir_p build_dir

    cmake_flags = ""

    if !compiler[:cc_bin].nil?
      cmake_flags = "-DCMAKE_C_COMPILER:PATH=\"#{compiler[:cc_bin]}\" -DCMAKE_CXX_COMPILER:PATH=\"#{compiler[:cxx_bin]}\""
    end

    out, err, result = run_script(
      ["cd #{build_dir} && #{@config.cmake_bin} ../ #{cmake_flags} -DCPACK_PACKAGE_FILE_NAME:STRING=#{package_name compiler} -DCMAKE_BUILD_TYPE:STRING=#{build_type} -G \"#{compiler[:build_generator]}\""])


    cmake_result = process_cmake_results(compiler, src_dir, build_dir, out, err, result, false)

    if !cmake_result
      return false;
    end

    if @config.os != "Windows"
      build_switches = "-j4"
    else
      build_switches = ""
    end

    out, err, result = run_script(
        ["cd #{build_dir} && #{@config.cmake_bin} --build . --config #{build_type} --use-stderr -- #{build_switches}"])

    msvc_success = process_msvc_results(compiler, src_dir, build_dir, out, err, result)
    gcc_success = process_gcc_results(compiler, src_dir, build_dir, out, err, result)
    return msvc_success && gcc_success
  end

  def cmake_package(compiler, src_dir, build_dir, build_type)
    pack_stdout, pack_stderr, pack_result = run_script(
      ["cd #{build_dir} && #{@config.cpack_bin} -G #{compiler[:build_package_generator]} -C #{build_type}"])

    cmake_result = process_cmake_results(compiler, src_dir, build_dir, pack_stdout, pack_stderr, pack_result, true)

    if !cmake_result
      raise "Error building package: #{pack_stderr}"
    end

    return "#{build_dir}/#{package_full_name compiler}"
  end



  def do_package compiler
    @logger.info("Beginning packaging phase #{is_release} #{needs_release_package(compiler)}")

    if is_release # && needs_release_package(compiler)
      src_dir = "#{build_base_name compiler}-release"
      build_dir = "#{src_dir}/build"

      @created_dirs << src_dir
      @created_dirs << build_dir

      checkout src_dir

      case @config.engine
      when "cmake"
        cmake_build compiler, src_dir, build_dir, "Release"
      else
        raise "Unknown Build Engine"
      end

      begin 
        @package_location = cmake_package compiler, src_dir, build_dir, "Release"
      rescue => e
        @logger.error("Error creating package #{e}")
      end

    end
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

  def needs_run compiler
    return true if @test_run

    file_names = []
    begin 
      files = @client.content @config.results_repository, :path=>@config.results_path

      files.each { |f|
        file_names << f.name
      }
    rescue Octokit::NotFound => e
      # repository doesn't have a _posts folder yet
    end

    file_names.each{ |f|
      return false if f.end_with? results_file_name(compiler)
    }

    return true
  end

  def cmake_test(compiler, src_dir, build_dir, build_type)
    test_stdout, test_stderr, test_result = run_script(["cd #{build_dir} && #{@config.ctest_bin} --timeout 3600 -D ExperimentalTest -C #{build_type}"]);
    @test_results = process_ctest_results compiler, src_dir, build_dir, test_stdout, test_stderr, test_result
  end

  def do_test(compiler)
    src_dir = build_base_name compiler
    build_dir = "#{build_base_name compiler}/build"

    @created_dirs << src_dir
    @created_dirs << build_dir

    checkout_succeeded  = checkout src_dir

    case @config.engine
    when "cmake"
      build_succeeded = cmake_build compiler, src_dir, build_dir, "Debug" if checkout_succeeded
      cmake_test compiler, src_dir, build_dir, "Debug" if build_succeeded 
    else
      raise "Unknown Build Engine"
    end
  end

  def unhandled_failure e
    @failure = e
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

  def clean_up compiler
    if !@test_run
      @created_dirs.each { |d|
        begin 
          FileUtils.rm_rf(d)
        rescue => e
          @logger.error("Error cleaning up directory #{e}")
        end
      }
    end
  end

  def next_build
    @created_dirs = []
    @package_location = nil
    @test_results = nil
    @build_results = SortedSet.new()
    @package_results = SortedSet.new()
    @dateprefix = nil
  end

  def post_results compiler, pending
    if @dateprefix.nil?
      @dateprefix = DateTime.now.utc.strftime("%F")
    end

    test_results_data = []

    test_results_passed = 0
    test_results_total = 0

    if !@test_results.nil?
      @test_results.each { |t| 
        test_results_total += 1
        test_results_passed += 1 if t.passed

        test_results_data << t.inspect;
      }
    end

    build_errors = 0
    build_warnings = 0
    build_results_data = []

    if !@build_results.nil?
      @build_results.each { |b|
        build_errors += 1 if b.is_error
        build_warnings += 1 if b.is_warning

        build_results_data << b.inspect
      }
    end

    package_errors = 0
    package_warnings = 0
    package_results_data = []

    if !@package_results.nil?
      @package_results.each { |b|
        package_errors += 1 if b.is_error
        package_warnings += 1 if b.is_warning

        package_results_data << b.inspect
      }
    end



    json_data = {"build_results"=>build_results_data, "test_results"=>test_results_data, "failure" => @failure, "package_results"=>package_results_data}

    json_document = 
<<-eos
---
title: #{build_base_name compiler}
permalink: #{build_base_name compiler}.html
tags: data
layout: ci_results
date: #{DateTime.now.utc.strftime("%F %T")}
unhandled_failure: #{!@failure.nil?}
build_error_count: #{build_errors}
build_warning_count: #{build_warnings}
package_error_count: #{package_errors}
package_warning_count: #{package_warnings}
test_count: #{test_results_total}
test_passed_count: #{test_results_passed}
repository: #{@repository}
compiler: #{@config.compiler}
compiler_version: #{@config.compiler_version}
architecture: #{@config.architecture}
os: #{@config.os}
os_release: #{@config.os_release}
is_release: #{is_release}
release_packaged: #{!@package_location.nil?}
tag_name: #{@tag_name}
commit_sha: #{@commit_sha}
branch_name: #{@branch_name}
test_run: #{!@test_results.nil?}
pull_request_issue_id: "#{pull_request_issue_id}"
pull_request_base_repository: #{@pull_request_base_repository}
pull_request_base_ref: #{@pull_request_base_ref}
device_id: #{device_id compiler}
pending: #{pending}
---

#{json_data.to_json}

eos

    test_failed = false
    if @test_results.nil?
      test_color = "red"
      test_failed = true
      test_string = "NA"
    else
      if test_results_total == 0
        test_percent = 100.0
      else 
        test_percent = (test_results_passed / test_results_total) * 100.0
      end

      if test_percent > 99.99
        test_color = "green"
      elsif test_percent > 90.0
        test_color = "yellow"
      else
        test_color = "red"
        test_failed = true
      end
      test_string = "#{test_percent}%25"
    end

    test_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Test Badge](http://img.shields.io/badge/tests%20passed-#{test_string}-#{test_color}.svg)</a>"

    build_failed = false
    if build_errors > 0
      build_color = "red"
      build_string = "failing"
      build_failed = true
    elsif build_warnings > 0
      build_color = "yellow"
      build_string = "warnings"
    else
      build_color = "green"
      build_string = "passing"
    end

    build_badge = "<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>![Build Badge](http://img.shields.io/badge/build%20status-#{build_string}-#{build_color}.svg)</a>"

    failed = build_failed || test_failed || !@failure.nil?
    github_status = pending ? "pending" : (failed ? "failure" : "success")

    if pending 
      github_status_message = "Build Pending"
    else
      if build_failed
        github_status_message = "Build Failed"
      elsif test_failed
        github_status_message = "Tests Failed"
      else
        github_status_message = "OK (#{test_results_passed} of #{test_results_total} tests passed)"
      end
    end

    if !@failure.nil?    
      github_document = 
<<-eos
<a href='#{@config.results_base_url}/#{build_base_name compiler}.html'>Unhandled Fundamental Failure</a>
eos
    else
      github_document = 
<<-eos
#{device_id compiler}: #{(failed) ? "Failed" : "Succeeded"}

#{build_badge} #{test_badge}
eos
    end

    if !@test_run
      begin
        if pending
          @logger.info("Posting pending results file");
          response = @client.create_contents(@config.results_repository,
                                             "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
          "Commit initial build results file: #{@dateprefix}-#{results_file_name compiler}",
          json_document)
          @logger.debug("Results document sha set: #{response.content.sha}")

          @results_document_sha = response.content.sha

        else
          if @results_document_sha.nil?
            raise "Error, no prior results document sha set"
          end

          @logger.info("Updating contents with sha #{@results_document_sha}")
          response = @client.update_contents(@config.results_repository,
                                             "#{@config.results_path}/#{@dateprefix}-#{results_file_name compiler}",
          "Commit final build results file: #{@dateprefix}-#{results_file_name compiler}",
          @results_document_sha,
            json_document)
        end
      rescue => e
        @logger.error "Error creating / updating results contents file: #{e}"
        raise e
      end

      if !pending && @config.post_results_comment
        if !@commit_sha.nil? && @repository == @config.repository
          response = @client.create_commit_comment(@config.repository, @commit_sha, github_document)
        elsif !pull_request_issue_id.nil?
          response = @client.add_comment(@config.repository, pull_request_issue_id, github_document);
        end
      end

      if !@commit_sha.nil? && @config.post_results_status
        response = @client.create_status(@config.repository, @commit_sha, github_status, :context=>device_id(compiler), :target_url=>"#{@config.results_base_url}/#{build_base_name compiler}.html", :description=>github_status_message, :accept => Octokit::Client::Statuses::COMBINED_STATUS_MEDIA_TYPE)
      end

      if !@package_location.nil? && @config.post_release_package
        @client.upload_asset(@release_url, @package_location, :content_type=>compiler[:package_mimetype], :name=>Pathname.new(@package_location).basename.to_s)
      end
    else 
      File.open("#{@dateprefix}-#{results_file_name compiler}", "w+") { |f| f.write(json_document) }
      File.open("#{@dateprefix}-COMMENT-#{results_file_name compiler}", "w+") { |f| f.write(github_document) }
    end


  end

end

class Build
  def initialize(token, repository)
    @client = Octokit::Client.new(:access_token=>token)
    @token = token
    @repository = repository
    @user = @client.user
    @user.login
    @potential_builds = []
    @logger = Logger.new(STDOUT)
   end

  def query_releases
    releases = @client.releases(@repository)

    releases.each { |r|
      begin 
        @potential_builds << PotentialBuild.new(@client, @token, @repository, r.tag_name, nil, nil, r.url, r.assets, nil, nil, nil)
      rescue => e
        @logger.info("Skipping potential build: #{e.backtrace} #{r}")
      end
    }
  end

  def query_branches
    branches = @client.branches(@repository)

    branches.each { |b| 
      begin 
        @potential_builds << PotentialBuild.new(@client, @token, @repository, nil, b.commit.sha, b.name, nil, nil, nil, nil, nil)
      rescue => e
        @logger.info("Skipping potential build: #{e.backtrace} #{b}")
      end
    }
  end

  def query_pull_requests
    pull_requests = @client.pull_requests(@repository, :state=>"open")

    pull_requests.each { |p| 
      if p.head.repo.full_name == p.base.repo.full_name
        @logger.info("Skipping pullrequest originating from head repo");
      else
        begin 
          @potential_builds << PotentialBuild.new(@client, @token, p.head.repo.full_name, nil, p.head.sha, p.head.ref, nil, nil, p.number, p.base.repo.full_name, p.base.ref)
        rescue => e
          @logger.info("Skipping potential build: #{e.backtrace} #{p}")
        end
      end
    }
  end


  def potential_builds
    @potential_builds
  end
end



@logger = Logger.new(STDOUT)


@logger.info "Args: #{ARGV.length}"

for conf in 1..ARGV.length-1
  @logger.info "Loading configuration #{ARGV[conf]}"
  b = Build.new(ARGV[0], ARGV[conf])

  @logger.info "Querying for updated branches"
  b.query_releases
  b.query_branches
  b.query_pull_requests


  b.potential_builds.each { |p|

    @logger.info "Looping over compilers"
    p.compilers.each { |compiler|

      begin
        # reset potential build for the next build attempt
        p.next_build
#        p.set_test_run true

        if p.needs_run compiler
          @logger.info "Beginning build for #{compiler} #{p.descriptive_string}"
          p.post_results compiler, true
          begin 
            p.do_package compiler
            p.do_test compiler
          rescue => e
            @logger.error "Logging unhandled failure #{e} #{e.backtrace}"
            p.unhandled_failure e
          end 
          p.post_results compiler, false
          p.clean_up compiler
        else
          @logger.info "Skipping build, already completed, for #{compiler} #{p.descriptive_string}"
        end
      rescue => e
        @logger.error "Error creating build: #{compiler} #{p.descriptive_string}: #{e} #{e.backtrace}"
      end
    }
  }
end

