require 'rbconfig'
require 'rspec'
require_relative '../lib/runners'

class DummyConfig
  attr_reader :os
  def initialize(os_name)
    @os = os_name
  end
end

describe 'Runners Testing' do
  include Runners
  before do
    @config = DummyConfig.new('Linux')
  end
  context 'when running run_scripts' do
    it 'should grab stdout for a simple script call' do
      dir1 = Dir.mktmpdir
      open(File.join(dir1, 'a'), 'w') { |f| f << "HAI" }
      open(File.join(dir1, 'b'), 'w') { |f| f << "HAI" }
      out, = run_scripts(@config, ["ls #{dir1}"])
      expect(out).to eql "a\nb\n"
    end
    it 'should return empty output for successful but empty scripts' do
      dir1 = Dir.mktmpdir
      out, = run_scripts(@config, ["ls #{dir1}"])
      expect(out).to eql ''
    end
    it 'should return a non-zero result when any script fails' do
      dir1 = Dir.mktmpdir
      _, _, result = run_scripts(@config, ["ls #{dir1}", "ls #{dir1}asdf", "ls #{dir1}"])
      expect(result > 0).to be_truthy  # an ls to an invalid directory returns 2 on Linux, 1 on Mac...GROSS
    end
    it 'should capture stuff on stdout and stderr both' do
      dir1 = Dir.mktmpdir
      script_file = File.join(dir1, 'a')
      open(script_file, 'w') { |f| f << "#!/bin/bash\necho Hello\necho something >&2\nexit 0" }
      out, err, result = run_scripts(@config, ["bash #{script_file}"])
      expect(out).to eql "Hello\n"
      expect(err).to eql "something\n"
      expect(result).to eql 0
    end
    it 'should accumulate output of multiple scripts' do
      dir1 = Dir.mktmpdir
      script_file = File.join(dir1, 'a')
      open(script_file, 'w') { |f| f << "#!/bin/bash\necho Hello\necho something >&2\nexit 0" }
      out, err, result = run_scripts(@config, ["bash #{script_file}", "bash #{script_file}"])
      expect(out).to eql "Hello\nHello\n"
      expect(err).to eql "something\nsomething\n" unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      expect(result).to eql 0
    end
    it 'should timeout on supported platforms' do
#        run_scripts(@config
    end
    it 'should handle long-ish running scripts nicely' do
      dir1 = Dir.mktmpdir
      script_file = File.join(dir1, 'a')
      open(script_file, 'w') { |f| f << "#!/bin/bash\necho Hello\nsleep 2\necho World\nsleep 2\necho OK\nexit 0" }
      out, err, result = run_scripts(@config, ["bash #{script_file}"])
      expect(out).to include "Hello", "World", "OK"
      expect(result).to eql 0
    end
  end
end
