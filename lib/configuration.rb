# frozen_string_literal: true

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
    path_array = path_array.concat(extra_paths) unless extra_paths.nil?

    path_array.each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return Pathname.new(exe).cleanpath.to_s if File.executable? exe
      end
    end
    nil
  end

  def load_configuration(location, ref, is_release)
    load_yaml = lambda do |name, this_location, this_ref|
      if !this_location.nil? && !name.nil?
        begin
          content = @client.content(this_location, :path => name, :ref => this_ref)
          contents = content.content
          return_value = YAML.load(Base64.decode64(contents.to_s))
        rescue SyntaxError => e
          raise "#{e.message} while parsing #{name}@#{this_ref}"
        rescue => e
          $logger.info("Unable to load yaml file from repository: #{this_location}/#{name}@#{this_ref} error: #{e}")

          path = File.expand_path(name, this_location)
          $logger.info("Attempting to load yaml config file: #{path}")
          if File.exist?(path)
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

    symbolize = lambda do |obj|
      if obj.is_a? Hash
        return obj.reduce({}) do |memo, (k, v)|
          memo.tap { |m| m[k.to_sym] = symbolize(v) }
        end
      elsif obj.is_a? Array
        return obj.reduce([]) do |memo, v|
          memo << symbolize(v)
          memo
        end
      end
      obj
    end

    if RUBY_PLATFORM.match?(/darwin/i)
      os_distribution = nil
      os_version = 'MacOS'
      ver_string = `uname -v`.strip
      /.* Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\.(?<ver_patch>[0-9]+).*:.*/ =~ ver_string # rubocop:disable Lint/UselessAssignment
      # the darwin version number - 4 = the point release of macosx
      os_release = "10.#{ver_major.to_i - 4}"
    elsif RUBY_PLATFORM.match?(/linux/i)
      os_distribution = `lsb_release -is`.strip
      os_version = 'Linux'
      os_release = "#{`lsb_release -is`.strip}-#{`lsb_release -rs`.strip}"
    else
      os_distribution = nil
      os_version = 'Windows'
      ver_string = `cmd /c ver`.strip

      # rubymine doesn't understand that the RE capture groups are creating the ver_minor and ver_major variables
      /.* \[Version (?<ver_major>[0-9]+)\.(?<ver_minor>[0-9]+)\..*\]/ =~ ver_string
      os_release = nil
      if ver_major.to_i == 6
        if ver_minor.to_i == 1
          os_release = '7'
        elsif ver_minor.to_i == 2
          os_release = '8'
        elsif ver_minor.to_i == 3
          os_release = '8.1'
        end
      elsif ver_major.to_i == 10
        os_release = '10'
      end
      os_release = "Unknown-#{ver_major}.#{ver_minor}" if os_release.nil?
    end

    yaml_base_name = '.decent_ci'
    yaml_name = "#{yaml_base_name}.yaml"
    yaml_os_name = "#{yaml_base_name}-#{os_version}.yaml"
    yaml_os_distribution_name = nil

    yaml_os_distribution_name = "#{yaml_base_name}-#{os_version}-#{os_distribution}.yaml" unless os_distribution.nil?

    yaml_os_release_name = "#{yaml_base_name}-#{os_version}-#{os_release}.yaml"

    fileset = Set.new

    @client.content(location, :path => '.', :ref => ref).each do |path|
      fileset << path.name if path.name =~ /\.decent_ci.*/
    end

    $logger.info("For ref #{ref} .decent_ci files located: #{fileset.to_a}")

    raise 'No .decent_ci input files' if fileset.empty?

    base_yaml = nil
    os_yaml = nil
    os_distribution_yaml = nil
    os_distribution_release_yaml = nil
    base_yaml = load_yaml.call(yaml_name, location, ref) if fileset.include?(yaml_name)
    $logger.debug("Base yaml loaded: #{base_yaml}") unless base_yaml.nil?
    os_yaml = load_yaml.call(yaml_os_name, location, ref) if fileset.include?(yaml_os_name)
    $logger.debug("os yaml loaded: #{os_yaml}") unless os_yaml.nil?
    os_distribution_yaml = load_yaml.call(yaml_os_distribution_name, location, ref) if fileset.include?(yaml_os_distribution_name)
    $logger.debug("os distribution yaml loaded: #{os_distribution_yaml}") unless os_distribution_yaml.nil?
    os_distribution_release_yaml = load_yaml.call(yaml_os_release_name, location, ref) if fileset.include?(yaml_os_release_name)
    $logger.debug("os distribution release yaml loaded: #{os_distribution_release_yaml}") unless os_distribution_release_yaml.nil?

    cmake_paths = ['C:\\Program Files\\CMake\\bin',
                   'C:\\Program Files (x86)\\CMake\\bin',
                   'C:\\Program Files\\CMake 3.0\\bin',
                   'C:\\Program Files (x86)\\CMake 3.0\\bin',
                   'C:\\Program Files\\CMake 2.8\\bin',
                   'C:\\Program Files (x86)\\CMake 2.8\\bin',
                   'C:\\ProgramData\\chocolatey\\bin']

    result_yaml = {
      :os => os_version,
      :os_release => os_release,
      :engine => 'cmake',
      :post_results_comment => true,
      :post_results_status => true,
      :post_release_package => true,
      :cmake_bin => "\"#{which('cmake', cmake_paths)}\"",
      :ctest_bin => "\"#{which('ctest', cmake_paths)}\"",
      :cpack_bin => "\"#{which('cpack', cmake_paths)}\""
    }

    result_yaml.merge!(base_yaml) unless base_yaml.nil?
    result_yaml.merge!(os_yaml) unless os_yaml.nil?
    result_yaml.merge!(os_distribution_yaml) unless os_distribution_yaml.nil?
    result_yaml.merge!(os_distribution_release_yaml) unless os_distribution_release_yaml.nil?

    result_yaml = symbolize.call(result_yaml)

    $logger.info("Final merged configuration: #{result_yaml}")

    configuration = OpenStruct.new(result_yaml)

    raise 'No compilers defined' if configuration.compilers.nil?

    # go through the list of compilers specified and fill in reasonable defaults
    # if there are not any specified already
    # noinspection RubyScope
    configuration.compilers.each do |compiler|
      $logger.debug("Working on compiler: #{compiler[:name]}")

      compiler[:architecture_description] = if compiler[:architecture].nil? || compiler[:architecture] == ''
                                              if compiler[:name] == 'Visual Studio'
                                                'i386'
                                              else
                                                RbConfig::CONFIG['host_cpu']
                                              end
                                            else
                                              compiler[:architecture]
                                            end

      if compiler[:version].nil?
        case compiler[:name]
        when 'Visual Studio'
          raise 'Version number for visual studio must be provided'
        when 'clang'
          /.*clang version (?<version>([0-9]+\.?)+).*/ =~ `clang --version`
          compiler[:version] = version
        when 'gcc'
          compiler[:version] = `gcc -dumpversion`
        when 'cppcheck'
          /.*Cppcheck (?<version>([0-9]+\.?)+).*/ =~ `cppcheck --version`
          compiler[:version] = version
        end
      end

      if compiler[:name] != 'custom_check' && compiler[:name] != 'cppcheck' && compiler[:name] != 'Visual Studio' && (compiler[:cc_bin].nil? || compiler[:cxx_bin].nil?)
        case compiler[:name]
        when 'clang'
          potential_name = which("clang-#{compiler[:version]}")
          if !potential_name.nil?
            compiler[:cc_bin] = potential_name
            compiler[:cxx_bin] = which("clang++-#{compiler[:version]}")
          else
            compiler[:cc_bin] = which('clang')
            compiler[:cxx_bin] = which('clang++')
          end
        when 'gcc'
          potential_name = which("gcc-#{compiler[:version]}")
          if !potential_name.nil?
            compiler[:cc_bin] = potential_name
            compiler[:cxx_bin] = which("g++-#{compiler[:version]}")
          else
            compiler[:cc_bin] = which('gcc')
            compiler[:cxx_bin] = which('g++')
          end
        end

        if compiler[:cc_bin].nil? || compiler[:cxx_bin].nil? || (`#{compiler[:cc_bin]} --version` !~ /.*#{compiler[:version]}/) || (`#{compiler[:cxx_bin]} --version` !~ /.*#{compiler[:version]}/)
          raise "Unable to find appropriate compiler for: #{compiler[:name]} version #{compiler[:version]}"
        end
      end

      compiler[:analyze_only] = false if compiler[:analyze_only].nil?

      compiler[:release_only] = false if compiler[:release_only].nil?

      if compiler[:name] == 'cppcheck' && compiler[:bin].nil?
        potential_name = which("cppcheck-#{compiler[:version]}")
        compiler[:analyze_only] = true
        compiler[:bin] = if !potential_name.nil?
                           potential_name
                         else
                           which('cppcheck')
                         end

        raise "Unable to find appropriate compiler for: #{compiler[:name]} version #{compiler[:version]}" if compiler[:bin].nil? || (`#{compiler[:bin]} --version` !~ /.*#{compiler[:version]}/)
      end

      compiler[:analyze_only] = true if compiler[:name] == 'custom_check'

      if compiler[:skip_packaging].nil?
        compiler[:skip_packaging] = false
      elsif (compiler[:skip_packaging] =~ /true/i) || compiler[:skip_packaging] == true
        compiler[:skip_packaging] = true
      end

      description = compiler[:name].gsub(/\s+/, '')
      description = "#{description}-#{compiler[:version]}" if !compiler[:version].nil? && compiler[:version] != ''

      compiler[:description] = description

      if compiler[:build_package_generator].nil? || compiler[:build_package_generator] == ''
        case configuration.os
        when 'Windows'
          compiler[:build_package_generator] = 'NSIS'
        when 'Linux'
          compiler[:build_package_generator] = if configuration.os_release =~ /.*ubuntu.*/i || configuration.os_release =~ /.*deb.*/i || configuration.os_release =~ /.*mint.*/i
                                                 'DEB'
                                               else
                                                 'RPM'
                                               end
        when 'MacOS'
          compiler[:build_package_generator] = 'IFW'
        end
      end

      compiler[:build_type] = 'Release' if compiler[:build_type].nil? || compiler[:build_type] == ''

      if compiler[:build_generator].nil? || compiler[:build_generator] == ''
        compiler[:target_arch] = nil
        case compiler[:name]
        when /.*Visual Studio.*/i
          raise 'Decent CI currently only deployed with Visual Studio version 16 (2019)' if compiler[:version] != 16

          generator = 'Visual Studio 16 2019'
          # Visual Studio 2019+ generator behaves slightly different, need to add -A
          compiler[:target_arch] = if compiler[:architecture].match?(/.*64.*/)
                                     'x64'
                                   else
                                     'Win32'
                                   end
          compiler[:build_generator] = generator
        else
          compiler[:build_generator] = 'Unix Makefiles'
        end
      end

      if compiler[:package_extension].nil? || compiler[:package_extension] == ''
        case compiler[:build_package_generator]
        when /.*NSIS.*/
          compiler[:package_extension] = 'exe'
        when /.*IFW.*/
          compiler[:package_extension] = 'dmg'
        when /.*STGZ.*/
          compiler[:package_extension] = 'sh'
        when /T.*/
          /T(?<tar_type>[A-Z]+)/ =~ compiler[:build_package_generator]
          compiler[:package_extension] = "tar.#{tar_type.downcase}"
        else
          compiler[:package_extension] = compiler[:build_package_generator].downcase
        end
      end

      compiler[:package_mimetype] = case compiler[:package_extension]
                                    when 'DEB'
                                      'application/x-deb'
                                    else
                                      'application/octet-stream'
                                    end

      compiler[:skip_regression] = false if compiler[:skip_regression].nil?

      compiler[:collect_performance_results] = false if compiler[:collect_performance_results].nil?

      compiler[:ctest_filter] = '' if compiler[:ctest_filter].nil?

      compiler[:coverage_base_dir] = '' if compiler[:coverage_base_dir].nil?

      compiler[:coverage_enabled] = false if compiler[:coverage_enabled].nil?

      compiler[:coverage_pass_limit] = 90 if compiler[:coverage_pass_limit].nil?

      compiler[:coverage_warn_limit] = 75 if compiler[:coverage_warn_limit].nil?

      if is_release && !compiler[:cmake_extra_flags_release].nil?
        compiler[:cmake_extra_flags] = compiler[:cmake_extra_flags_release]
      elsif compiler[:cmake_extra_flags].nil?
        compiler[:cmake_extra_flags] = ''
      end

      next unless compiler[:num_parallel_builds].nil?

      num_processors = processor_count
      num_processors -= 1 if num_processors > 2
      compiler[:num_parallel_builds] = num_processors
    end

    configuration.tests_dir = '' if configuration.tests_dir.nil?

    configuration.aging_pull_requests_notification = true if configuration.aging_pull_requests_notification.nil?

    configuration.aging_pull_requests_numdays = 7 if configuration.aging_pull_requests_numdays.nil?

    configuration.test_pass_limit = 99.9999 if configuration.test_pass_limit.nil?

    configuration.test_warn_limit = 90.00 if configuration.test_warn_limit.nil?

    configuration
  end
end
