require 'rspec'
require_relative '../lib/processor'

describe 'Processor Class' do
  context 'When getting processor count' do
    it 'should get an integer' do
      expect(processor_count.to_i).to be_an_instance_of(Integer)
    end
  end
end
