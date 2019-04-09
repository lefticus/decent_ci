# encoding: UTF-8 

require_relative 'processor.rb'

## tools for loading and parsing of yaml config files
## and filling in the details 
module Configuration

  # Cross-platform way of finding an executable in the $PATH.
  #
  #   which('ruby') #=> /usr/bin/ruby
  def which(cmd, extra_paths = nil)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    path_array = ENV['PATH'].split(File::PATH_SEPARATOR)
    unless extra_paths.nil?
      path_array = path_array.concat(extra_paths)
    end

    path_array.each do |path|
      exts.each {|ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return Pathname.new(exe).cleanpath.to_s if File.executable? exe
      }
    end
    nil
  end

  def load_configuration(location, ref, is_release)
    def load_yaml(name, location, ref)
      if !location.nil? && !name.nil?
        begin
          content = @client.content(location, {:path => name, :ref => ref})
          contents = content.content
          return_value = YAML.load(Base64.decode64(contents.to_s))
        rescue SyntaxError => e
          raise "#{e.message} while parsing #{name}@#{ref}"
        rescue => e
          $logger.info("Unable to load yaml file from repository: #{location}/#{name}@#{ref} error: #{e}")

          path = File.expand_path(name, location)
          $logger.info("Attempting to load yaml config file: #{path}")
          if File.exists?(path)
            return_value = YAML.load_file(path)
          else
            $logger.info("yaml file does not exist: #{path}")
            return_value = nil
          end
        end
      else
        return_value = nil
      end
      return_value
    end

    def symbolize(obj)
      return obj.reduce({}) do |memo, (k, v)|
        memo.tap {|m| m[k.to_sym] = symbolize(v)}
      end if obj.is_a? Hash

      return obj.reduce([]) do |memo, v|
        memo << symbolize(v); memo
      end if obj.is_a? Array

      obj
    end

    if RUBY_PLATFORM =~ /darwin/i
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

      # rubymine doesn't understand that the RE capture groups are creating the ver_minor and ver_major variables
      ver_minor = nil
      ver_major = nil
      /.* \[Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\..*\]/ =~ ver_string
      os_release = nil
      if ver_major.to_i == 6
        if ver_minor.to_i == 1
          os_release = "7"
        elsif ver_minor.to_i == 2
          os_release = "8"
        elsif ver_minor.to_i == 3
          os_release = "8.1"
        end
      elsif ver_major.to_i == 10
        os_release = "10"
      end
      if os_release.nil?
        os_release = "Unknown-#{ver_major}.#{ver_minor}"
      end
    end

    yaml_base_name = ".decent_ci"
    yaml_name = "#{yaml_base_name}.yaml"
    yaml_os_name = "#{yaml_base_name}-#{os_version}.yaml"
    yaml_os_distribution_name = nil

    unless os_distribution.nil?
      yaml_os_distribution_name = "#{yaml_base_name}-#{os_version}-#{os_distribution}.yaml"
    end

    yaml_os_release_name = "#{yaml_base_name}-#{os_version}-#{os_release}.yaml"

    fileset = Set.new

    @client.content(location, {:path => ".", :ref => ref}).each {|path|
      if path.name =~ /\.decent_ci.*/
        fileset << path.name
      end
    }

    $logger.info("For ref #{ref} .decent_ci files located: #{fileset.to_a}")

    raise "No .decent_ci input files" if fileset.empty?

    base_yaml = nil
    os_yaml = nil
    os_distribution_yaml = nil
    os_distribution_release_yaml = nil
    base_yaml = load_yaml(yaml_name, location, ref) if fileset.include?(yaml_name)
    $logger.debug("Base yaml loaded: #{base_yaml}") unless base_yaml.nil?
    os_yaml = load_yaml(yaml_os_name, location, ref) if fileset.include?(yaml_os_name)
    $logger.debug("os yaml loaded: #{os_yaml}") unless os_yaml.nil?
    os_distribution_yaml = load_yaml(yaml_os_distribution_name, location, ref) if fileset.include?(yaml_os_distribution_name)
    $logger.debug("os distribution yaml loaded: #{os_distribution_yaml}") unless os_distribution_yaml.nil?
    os_distribution_release_yaml = load_yaml(yaml_os_release_name, location, ref) if fileset.include?(yaml_os_release_name)
    $logger.debug("os distribution release yaml loaded: #{os_distribution_release_yaml}") unless os_distribution_release_yaml.nil?

    cmake_paths = ["C:\\Program Files\\CMake\\bin",
                   "C:\\Program Files (x86)\\CMake\\bin",
                   "C:\\Program Files\\CMake 3.0\\bin",
                   "C:\\Program Files (x86)\\CMake 3.0\\bin",
                   "C:\\Program Files\\CMake 2.8\\bin",
                   "C:\\Program Files (x86)\\CMake 2.8\\bin",
                   "C:\\ProgramData\\chocolatey\\bin"]

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

    result_yaml.merge!(base_yaml) unless base_yaml.nil?
    result_yaml.merge!(os_yaml) unless os_yaml.nil?
    result_yaml.merge!(os_distribution_yaml) unless os_distribution_yaml.nil?
    result_yaml.merge!(os_distribution_release_yaml) unless os_distribution_release_yaml.nil?

#    if result_yaml[:extra_tests_branches].nil?
#      result_yaml[:extra_tests_branches] = []
#    end

    result_yaml = symbolize(result_yaml)

    $logger.info("Final merged configuration: #{result_yaml}")


    configuration = OpenStruct.new(result_yaml)

    raise "No compilers defined" if configuration.compilers.nil?

# go through the list of compilers specified and fill in reasonable defaults
# if there are not any specified already
    # noinspection RubyScope
    configuration.compilers.each { |compiler|
      $logger.debug("Working on compiler: #{compiler[:name]}")

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
        when "cppcheck"
          /.*Cppcheck (?<version>([0-9]+\.?)+).*/ =~ `cppcheck --version`
          compiler[:version] = version
        end
      end

      if compiler[:name] != "custom_check" && compiler[:name] != "cppcheck" && compiler[:name] != "Visual Studio" && (compiler[:cc_bin].nil? || compiler[:cxx_bin].nil?)
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

        if compiler[:cc_bin].nil? || compiler[:cxx_bin].nil? || !(`#{compiler[:cc_bin]} --version` =~ /.*#{compiler[:version]}/) || !(`#{compiler[:cxx_bin]} --version` =~ /.*#{compiler[:version]}/)
          raise "Unable to find appropriate compiler for: #{compiler[:name]} version #{compiler[:version]}"
        end
      end

      if compiler[:analyze_only].nil?
        compiler[:analyze_only] = false
      end

      if compiler[:release_only].nil?
        compiler[:release_only] = false
      end

      if compiler[:name] == "cppcheck" && compiler[:bin].nil?
        potential_name = which("cppcheck-#{compiler[:version]}")
        compiler[:analyze_only] = true
        if !potential_name.nil?
          compiler[:bin] = potential_name
        else
          compiler[:bin] = which("cppcheck")
        end
        if compiler[:bin].nil? || !(`#{compiler[:bin]} --version` =~ /.*#{compiler[:version]}/)
          raise "Unable to find appropriate compiler for: #{compiler[:name]} version #{compiler[:version]}"
        end
      end

      if compiler[:name] == "custom_check"
        compiler[:analyze_only] = true
      end

      if compiler[:skip_packaging].nil?
        compiler[:skip_packaging] = false
      else
        if (compiler[:skip_packaging] =~ /true/i) || compiler[:skip_packaging] == true
          compiler[:skip_packaging] = true
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
          compiler[:build_package_generator] = "IFW"
        end
      end

      if compiler[:build_type].nil? || compiler[:build_type] == ""
        compiler[:build_type] = "Release"
      end

      if compiler[:build_generator].nil? || compiler[:build_generator] == ""
        compiler[:target_arch] = nil
        case compiler[:name]
        when /.*Visual Studio.*/i
          if compiler[:version] != 16
            raise "Decent CI currently only deployed with Visual Studio version 16 (2019)"
          end
          generator = "Visual Studio 16 2019"
          # Visual Studio 2019+ generator behaves slightly different, need to add -A
          if compiler[:architecture] =~ /.*64.*/
            compiler[:target_arch] = "x64"
          else
            compiler[:target_arch] = "Win32"
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
        when /.*IFW.*/
          compiler[:package_extension] = "dmg"
        when /.*STGZ.*/
          compiler[:package_extension] = "sh"
        when /T.*/
          /T(?<tar_type>[A-Z]+)/ =~ compiler[:build_package_generator]
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

      if compiler[:skip_regression].nil?
        compiler[:skip_regression] = false
      end

      if compiler[:collect_performance_results].nil?
        compiler[:collect_performance_results] = false
      end

      if compiler[:ctest_filter].nil?
        compiler[:ctest_filter] = ""
      end

      if compiler[:coverage_base_dir].nil?
        compiler[:coverage_base_dir] = ""
      end

      if compiler[:coverage_enabled].nil?
        compiler[:coverage_enabled] = false
      end

      if compiler[:coverage_pass_limit].nil?
        compiler[:coverage_pass_limit] = 90
      end

      if compiler[:coverage_warn_limit].nil?
        compiler[:coverage_warn_limit] = 75
      end

      if is_release && !compiler[:cmake_extra_flags_release].nil?
        compiler[:cmake_extra_flags] = compiler[:cmake_extra_flags_release]
      else
        if compiler[:cmake_extra_flags].nil?
          compiler[:cmake_extra_flags] = ""
        end
      end

      if compiler[:num_parallel_builds].nil?
        num_processors = processor_count
        if num_processors > 2
          num_processors -= 1
        end

        compiler[:num_parallel_builds] = num_processors
      end
    }

    if configuration.tests_dir.nil?
      configuration.tests_dir = ""
    end

    if configuration.aging_pull_requests_notification.nil?
      configuration.aging_pull_requests_notification = true
    end

    if configuration.aging_pull_requests_numdays.nil?
      configuration.aging_pull_requests_numdays = 7
    end

    if configuration.test_pass_limit.nil?
      configuration.test_pass_limit = 99.9999
    end

    if configuration.test_warn_limit.nil?
      configuration.test_warn_limit = 90.00
    end

    configuration
  end

end
