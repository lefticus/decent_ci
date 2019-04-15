require 'rspec'
require_relative '../lib/custom_check'
require_relative '../lib/runners'
require_relative '../lib/resultsprocessor'

describe 'CustomCheck Testing Successful Parsing' do
  include CustomCheck
  before do
    @dir = Dir.mktmpdir
    allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['a', 'b', 'c'])
    allow_any_instance_of(ResultsProcessor).to receive(:process_custom_check_results).and_return(true)
  end
  context 'when running custom_check' do
    it 'should run ok when process_custom_check_results succeeds' do
      compiler = { :commands => ['a'] }
      response = custom_check({}, compiler, "/src/dir", @dir)
      expect(response.length).to eql 1
      expect(response[0].passed).to be_truthy
    end
  end
end

describe 'CustomCheck Testing Failed Parsing' do
  include CustomCheck
  before do
    @dir = Dir.mktmpdir
    allow_any_instance_of(Runners).to receive(:run_scripts).and_return(['a', 'b', 'c'])
    allow_any_instance_of(ResultsProcessor).to receive(:process_custom_check_results).and_return(false)
  end
  context 'when running custom_check' do
    it 'should run ok when process_custom_check_results succeeds' do
      compiler = { :commands => ['a'] }
      response = custom_check({}, compiler, "/src/dir", @dir)
      expect(response.length).to eql 1
      expect(response[0].passed).to be_falsey
    end
  end
end

describe 'CustomCheck Testing Runtime Exception' do
  include CustomCheck
  before do
    @dir = Dir.mktmpdir
    allow_any_instance_of(Runners).to receive(:run_scripts).and_raise('ERROR')
  end
  it 'should return failure upon exception' do
    compiler = { :commands => ['a'] }
    response = custom_check({}, compiler, "/src/dir", @dir)
    expect(response.length).to eql 1
    expect(response[0].passed).to be_falsey
  end
end
