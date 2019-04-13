require 'rspec'
require_relative '../lib/configuration'

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
      ENV['PATH'] = [dir1, dir2, dir3].join(File::PATH_SEPARATOR)
      binary_path = which(binary_file_name)
      expect(binary_path).to include dir2
    end
  end
  context 'when calling load_yaml' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling symbolize' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling find_windows_6_release' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling establish_windows_characteristics' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling establish_os_characteristics' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling get_all_yaml_names' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling establish_base_configuration' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling find_valid_yaml_files' do
    it 'should return the correct SEFLKJ' do
    end
  end
  context 'when calling setup_compiler_architecture' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_architecture({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_architecture({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_architecture({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_version' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_version({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_version({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_version({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_description' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_description({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_description({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_description({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_package_generator' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_package_generator({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_package_generator({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_package_generator({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_package_extension' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_package_extension({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_package_extension({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_package_extension({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_package_mimetype' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_package_mimetype({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_package_mimetype({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_package_mimetype({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_extra_flags' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_extra_flags({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_extra_flags({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_extra_flags({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_num_processors' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_num_processors({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_num_processors({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_num_processors({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
    end
  end
  context 'when calling setup_compiler_cppcheck_bin' do
    it 'should return the correct SEFLKJ' do
      # expect(setup_compiler_cppcheck_bin({:ATTR => 'Already here'})).to eql 'Already here'
      # expect(setup_compiler_cppcheck_bin({:OTHERATTR => 'ONETHING'})).to include 'SOMETHING'
      # expect(setup_compiler_cppcheck_bin({:OTHERATTR => 'SECONDTHING'})).to include 'SOMETHINGELSE'
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
      expect(setup_compiler_target_arch({:name => 'Audial Studio 2443', :architecture => 'ABC'})).to be_nil
      expect(setup_compiler_target_arch({:name => 'Audial Studio 2443'})).to be_nil
    end
  end
  context 'when calling setup_gcc_style_cc_and_cxx' do
    it 'should return the right SEFLKJEFLKJEF' do
    end
  end
  context 'when calling setup_single_compiler' do
    it 'should properly setup all attributes of a single compiler' do
    end
  end
  context 'when calling load_configuration' do
    it 'should properly set up all compilers and other settings of all configurations' do
    end
  end
end
