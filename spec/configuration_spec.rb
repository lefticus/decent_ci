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
end
