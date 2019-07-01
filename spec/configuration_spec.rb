require 'base64'
require 'rspec'
require_relative '../lib/configuration'
require 'octokit'

class YamlResponse
  attr_reader :content
  def initialize(yaml_data_string)
    @content = yaml_data_string
  end
end

class NamedDummy
  attr_reader :name
  def initialize(this_name)
    @name = this_name
  end
end

describe 'Configuration Testing' do
  include Configuration
  context 'when calling which function to find executable' do
    it 'succeeds' do
      # create three temporary directories
      dir1 = Dir.mktmpdir
      dir2 = Dir.mktmpdir  # this will ultimately have a binary
      dir3 = Dir.mktmpdir
      # create the executable file, marking the executable flag with chmod
      binary_name = "runner"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      temp_file = File.join(dir2, binary_file_name)
      open(temp_file, 'w') { |f| f << "HAI" }
      File.chmod(0777, temp_file)
      # set up the PATH to hold all three dirs, it should only find the second
      cur_path = ENV['PATH']
      ENV['PATH'] = [dir1, dir2, dir3].join(File::PATH_SEPARATOR)
      binary_path = which(binary_file_name)
      expect(binary_path).to include dir2
      ENV['PATH'] = cur_path
    end
  end
  context 'when calling load_yaml' do
    it 'should return the correct hash data' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return(YamlResponse.new(Base64.encode64('data: stuff')))
      @client = Octokit::Client.new(:access_token => 'abc')
      yaml_hash_data = load_yaml('CMakeLists.txt', 'NREL/EnergyPlus', 'develop')
      expect(yaml_hash_data['data']).to eql 'stuff'
    end
    it 'should raise for bad yaml syntax' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return(YamlResponse.new(Base64.encode64("a: %1\"string\\\"")))
      @client = Octokit::Client.new(:access_token => 'abc')
      expect{ load_yaml('CMakeLists.txt', 'NREL/EnergyPlus', 'develop') }.to raise_error RuntimeError
    end
    it 'should find a local file at the path if remote is not found' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_raise('Hey, try local')
      @client = Octokit::Client.new(:access_token => 'abc')
      yaml_hash_data = load_yaml('dummy.yaml', 'spec/resources', 'develop')
      expect(yaml_hash_data['hello']).to eql 'world'
      expect(yaml_hash_data['foo']).to eql 'bar'
    end
    it 'should return nil if the yaml simply is not found' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_raise("Hey")
      @client = Octokit::Client.new(:access_token => 'abc')
      yaml_hash_data = load_yaml('CMakeLists.txt', 'NREL/EnergyPlus', 'develop')
      expect(yaml_hash_data).to be_nil
    end
  end
  context 'when calling find_valid_yaml_files' do
    it 'should find a couple dummy yaml files locally' do
      yaml_names = ['dummy.yaml', 'dummy2.yaml']
      fileset = ['dummy.yaml', 'dummy2.yaml']
      allow_any_instance_of(Octokit::Client).to receive(:content).and_raise('Hey, try local')
      @client = Octokit::Client.new(:access_token => 'abc')
      all_yamls = find_valid_yaml_files(yaml_names, 'spec/resources', 'abc123', fileset)
      expect(all_yamls.length).to eql 2
    end
    it 'should skip files not in the fileset' do
      yaml_names = ['dummy.yaml', 'dummy2.yaml']
      fileset = ['dummy2.yaml']
      allow_any_instance_of(Octokit::Client).to receive(:content).and_raise('Hey, try local')
      @client = Octokit::Client.new(:access_token => 'abc')
      all_yamls = find_valid_yaml_files(yaml_names, 'spec/resources', 'abc123', fileset)
      expect(all_yamls.length).to eql 1
    end
    it 'should return nil for failed lookups that do exist in fileset' do
      yaml_names = ['dummy.yaml', 'dummy2.yaml', 'dummy3.yaml']
      fileset = ['dummy.yaml', 'dummy2.yaml', 'dummy3.yaml']
      allow_any_instance_of(Octokit::Client).to receive(:content).and_raise('Hey, try local')
      @client = Octokit::Client.new(:access_token => 'abc')
      all_yamls = find_valid_yaml_files(yaml_names, 'spec/resources', 'abc123', fileset)
      expect(all_yamls.length).to eql 3
      expect(all_yamls.count(nil)).to eql 1
    end
  end
  context 'when calling symbolize' do
    it 'should return the correct symbolized hash' do
      compiler = {'name' => '', 'key 1' => '', 'key a' => '', 'alpha beta gamma' => ''}
      expect(compiler).to include 'name'
      symbolized = symbolize(compiler)
      expect(symbolized).to include :name
      expect(symbolized).to include 'key 1'.intern
      expect(symbolized).to include 'key a'.intern
      expect(symbolized).to include 'alpha beta gamma'.intern
    end
  end
  context 'when calling find_windows_6_release' do
    it 'should return a valid number' do
      expect(find_windows_6_release(0)).to be_nil
      expect(find_windows_6_release(1)).to eql '7'
      expect(find_windows_6_release(2)).to eql '8'
      expect(find_windows_6_release(3)).to eql '8.1'
      expect(find_windows_6_release(4)).to be_nil
    end
  end
  context 'when calling establish_os_characteristics' do
    it 'should return the a few OS parameters' do
      # the responses here will differ based on where we are testing it
      # we should really just make sure it runs without throwing and returns a list
      expect(establish_os_characteristics).to be_instance_of Array
    end
  end
  context 'when calling get_all_yaml_names' do
    it 'should return the a list of string file names' do
      response = get_all_yaml_names('Linux', '10', 'Distro')
      expect(response).to be_instance_of Array
      response.each do |filename|
        expect(filename).to be_instance_of String
      end
      response2 = get_all_yaml_names('Linux', '10', nil)
      expect(response2.select { |filename| filename.nil? }.length == 1).to be_truthy
    end
  end
  context 'when calling establish_base_configuration' do
    it 'should return a base config with some default keys' do
      c = establish_base_configuration('Linux', '32')
      expect(c).to include(:os, :os_release, :engine)
    end
  end
  context 'when calling find_valid_yaml_files' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling setup_compiler_architecture' do
    it 'should return the correct architecture' do
      expect(setup_compiler_architecture({:architecture => 'Already here'})).to eql 'Already here'
      expect(setup_compiler_architecture({:name => 'Visual Studio'})).to include 'i386'  # this is default, override with 64 as desired
      expect(setup_compiler_architecture({:name => 'All Other Compilers'})).to include '64'  # this assumes we only build on 64-bit systems
    end
  end
  context 'when calling setup_compiler_version' do
    it 'should return the given one if it exists' do
      expect(setup_compiler_version({:version => 'Already here'})).to eql 'Already here'
    end
    it 'should throw for invalid cases' do
      expect{ setup_compiler_version({:name => 'Visual Studio'}) }.to raise_error(RuntimeError)  # VS requires version
      expect{ setup_compiler_version({:name => 'OtherCompiler'}) }.to raise_error(RuntimeError)  # unknown compiler
    end
    it 'should find valid versions for gcc, clang, and handle cppcheck' do
      dir1 = Dir.mktmpdir
      cur_path = ENV['PATH']
      ENV['PATH'] = dir1
      binary_name = "cppcheck"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho Cppcheck 1" }
      File.chmod(0777, cc_binary)
      binary_name = "gcc"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\nprintf 2" }
      File.chmod(0777, cc_binary)
      binary_name = "clang"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho clang version 3" }
      File.chmod(0777, cc_binary)
      expect(setup_compiler_version({:name => 'cppcheck'})).to be_nil
      expect(setup_compiler_version({:name => 'gcc'})).to eql '2'
      expect(setup_compiler_version({:name => 'clang'})).to eql '3'
      ENV['PATH'] = cur_path
    end
  end
  context 'when calling setup_compiler_description' do
    it 'should return the correct SEFLKJ' do
      expect(setup_compiler_description({:name => 'Cool Compiler', :version => 1})).to be_a String
      expect{ setup_compiler_description({}) }.to raise_error(RuntimeError)  # need at least name
    end
  end
  context 'when calling setup_compiler_package_generator' do
    it 'should return the correct package generator' do
      expect(setup_compiler_package_generator({:build_package_generator => 'Already here'}, nil)).to eql 'Already here'
      expect(setup_compiler_package_generator({}, 'Windows')).to eql 'NSIS'
      expect(setup_compiler_package_generator({}, 'Linux')).to eql 'DEB'
      expect(setup_compiler_package_generator({}, 'MacOS')).to eql 'IFW'
      expect{ setup_compiler_package_generator({}, 'WHATOS') }.to raise_error(RuntimeError)  # bad OS
    end
  end
  context 'when calling setup_compiler_extra_flags' do
    it 'should return the correct flags for non-releases' do
      expect(setup_compiler_extra_flags({:cmake_extra_flags => '-dg 1'}, false)).to eql '-dg 1'
      expect(setup_compiler_extra_flags({}, false)).to eql ''
    end
    it 'should return the correct flags for release builds' do
      expect(setup_compiler_extra_flags({:cmake_extra_flags => '-dg 1', :cmake_extra_flags_release => '-dg 2'}, true)).to eql '-dg 2'
      expect(setup_compiler_extra_flags({}, true)).to eql ''
    end
  end
  context 'when calling setup_compiler_num_processors' do
    it 'should return a predefined value' do
      expect(setup_compiler_num_processors({:num_parallel_builds => 'ALPHA BUT OK'})).to eql 'ALPHA BUT OK'
    end
    it 'should return a valid number' do
      expect(setup_compiler_num_processors({})).to be_a Integer
    end
  end
  context 'when calling setup_compiler_cppcheck_bin' do
    it 'should return if already specified' do
      expect(setup_compiler_cppcheck_bin({:cppcheck_bin => 'Already here'}, nil)).to eql 'Already here'
    end
    it 'should fail if a version cannot be found' do
      cur_path = ENV['PATH']
      ENV['PATH'] = ''
      expect{ setup_compiler_cppcheck_bin({}, nil) }.to raise_error RuntimeError
      ENV['PATH'] = cur_path
    end
    it 'should find the cppcheck binary by name' do
      dir1 = Dir.mktmpdir
      binary_name = "cppcheck-1"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cc_binary)
      cur_path = ENV['PATH']
      ENV['PATH'] = dir1
      expect(setup_compiler_cppcheck_bin({}, 1)).to include cc_binary
      ENV['PATH'] = cur_path
    end
  end
  context 'when calling setup_compiler_build_generator' do
    it 'should return the correct build generator' do
      expect(setup_compiler_build_generator({:build_generator => 'Already here'})).to eql 'Already here'
      expect(setup_compiler_build_generator({:name => 'Visual Studio Hello'})).to include 'Visual Studio'
      expect(setup_compiler_build_generator({:name => 'gccc'})).to include 'Unix'
    end
  end
  context 'when calling setup_compiler_target_arch' do
    it 'should return the right architecture' do
      expect(setup_compiler_target_arch({:name => 'Visual Studio 2065', :architecture => 'WoW64'})).to eql 'x64'
      expect(setup_compiler_target_arch({:name => 'Visual Studio 2062', :architecture => 'Y63'})).to eql 'Win32'
      expect(setup_compiler_target_arch({:name => 'Visual Studio 2062'})).to eql 'Win32'  # default architecture
      expect(setup_compiler_target_arch({:name => 'Audial Studio 2443', :architecture => 'ABC'})).to eql 'ABC'  # return the architecture string if necessary
      expect(setup_compiler_target_arch({:name => 'Audial Studio 2443'})).to be_nil
    end
  end
  context 'when calling setup_gcc_style_cc_and_cxx' do
    it 'should return nil for invalid configurations' do
      cc, cxx = setup_gcc_style_cc_and_cxx({})
      expect(cc).to be_nil
      expect(cxx).to be_nil
      cc, cxx = setup_gcc_style_cc_and_cxx({:name => "Visual Studio"}) # invalid compiler for this function
      expect(cc).to be_nil
      expect(cxx).to be_nil
    end
    it 'should find gcc stuff on path without version number' do
      dir1 = Dir.mktmpdir
      binary_name = "gcc"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cc_binary)
      binary_name = "g++"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cxx_binary = File.join(dir1, binary_file_name)
      open(cxx_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cxx_binary)
      cur_path = ENV['PATH']
      ENV['PATH'] = dir1
      cc, cxx = setup_gcc_style_cc_and_cxx({:name => 'gcc'})
      expect(cc).to eql cc_binary
      expect(cxx).to eql cxx_binary
      ENV['PATH'] = cur_path
    end
    it 'should find gcc stuff on path with version number' do
      dir1 = Dir.mktmpdir
      binary_name = "gcc-1"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cc_binary)
      binary_name = "g++-1"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cxx_binary = File.join(dir1, binary_file_name)
      open(cxx_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cxx_binary)
      cur_path = ENV['PATH']
      ENV['PATH'] = dir1
      cc, cxx = setup_gcc_style_cc_and_cxx({:name => 'gcc', :version => "1"})
      expect(cc).to eql cc_binary
      expect(cxx).to eql cxx_binary
      ENV['PATH'] = cur_path
    end
    it 'should raise for invalid gcc version' do
      dir1 = Dir.mktmpdir
      binary_name = "gcc-1"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cc_binary)
      binary_name = "g++-1"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cxx_binary = File.join(dir1, binary_file_name)
      open(cxx_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cxx_binary)
      cur_path = ENV['PATH']
      ENV['PATH'] = dir1
      expect{ setup_gcc_style_cc_and_cxx({:name => 'gcc', :version => "2"}) }.to raise_error(CannotMatchCompiler)
      ENV['PATH'] = cur_path
    end
    it 'should find clang stuff on path with version number' do
      dir1 = Dir.mktmpdir
      binary_name = "clang"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cc_binary)
      binary_name = "clang++"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cxx_binary = File.join(dir1, binary_file_name)
      open(cxx_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cxx_binary)
      cur_path = ENV['PATH']
      ENV['PATH'] = dir1
      cc, cxx = setup_gcc_style_cc_and_cxx({:name => 'clang', :version => "1"})
      expect(cc).to eql cc_binary
      expect(cxx).to eql cxx_binary
      ENV['PATH'] = cur_path
    end
  end
  context 'when calling setup_single_compiler' do
    before do
      dir1 = Dir.mktmpdir
      binary_name = "gcc"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cc_binary = File.join(dir1, binary_file_name)
      open(cc_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cc_binary)
      binary_name = "g++"
      binary_extension = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';')[0] : ''
      binary_file_name = "#{binary_name}#{binary_extension}"
      cxx_binary = File.join(dir1, binary_file_name)
      open(cxx_binary, 'w') { |f| f << "#!/bin/bash\necho 1" }
      File.chmod(0777, cxx_binary)
      @cur_path = ENV['PATH']
      ENV['PATH'] = dir1
    end
    after do
      ENV['PATH'] = @cur_path
    end
    it 'should properly setup all attributes of a single compiler' do

    end
    it 'should accept a compiler with the minimal fields' do
      filled_compiler = setup_single_compiler({:name => "gcc"}, false, 'Linux')
      expect(filled_compiler).to include :cc_bin
      expect(filled_compiler).to include :cxx_bin
      expect(filled_compiler).to include :version
      expect(filled_compiler).to include :build_type
      expect(filled_compiler).to include :build_package_generator
      i = 1
    end
    it 'should throw for missing required fields' do

    end
  end
  context 'when calling load_configuration' do
    it 'should properly set up all compilers and other settings of all configurations' do
      allow_any_instance_of(Octokit::Client).to receive(:content).and_return([NamedDummy.new('.decent_ci.yaml')])
      @client = Octokit::Client.new(:access_token => 'abc')
      configuration = load_configuration('spec/resources', 'abc', false)
      expect(configuration.compilers.first[:name]).to eql 'gcc'
    end
    it 'should test lots more configuraitons' do
    end
  end
end
