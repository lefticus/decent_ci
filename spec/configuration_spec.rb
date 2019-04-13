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
  context 'when calling setup_compiler_target_arch' do
    it 'should return the right architecture' do
      expect(setup_compiler_target_arch({:name => 'Visual Studio 2065', :architecture => 'WoW64'})).to eql 'x64'
      expect(setup_compiler_target_arch({:name => 'Visual Studio 2062', :architecture => 'Y63'})).to eql 'Win32'
      expect(setup_compiler_target_arch({:name => 'Visual Studio 2062'})).to eql 'Win32'  # default architecture
      expect(setup_compiler_target_arch({:name => 'Audial Studio 2443', :architecture => 'ABC'})).to be_nil
      expect(setup_compiler_target_arch({:name => 'Audial Studio 2443'})).to be_nil
    end
  end
  context 'when calling setup_compiler_build_generator' do
    it 'should return the correct build generator' do
      expect(setup_compiler_build_generator({:build_generator => 'Already here'})).to eql 'Already here'
      expect(setup_compiler_build_generator({:name => 'Visual Studio Hello'})).to include 'Visual Studio'
      expect(setup_compiler_build_generator({:name => 'gccc'})).to include 'Unix'
    end
  end
end
