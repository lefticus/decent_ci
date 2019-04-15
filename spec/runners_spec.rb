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
    it 'should do a normal run for a simple script' do
      out, err, results = run_scripts(@config, ['ls'])
      i = 1
    end
    it 'should return SOMETHING for successful but empty scripts' do
        
    end
    it 'should return SOMETHING for a script that fails' do
    end
    it 'should capture stuff on stdout and stderr both' do
    end
    it 'should do multiple scripts properly' do
    end
    it 'should timeout on supported platforms' do
#        run_scripts(@config
    end
  end
end
