require 'rspec'
require_relative '../lib/testresult'

describe 'TestResult Testing' do
  context 'when constructing a testresult' do
    it 'should expose some variables as members' do
      tr = TestResult.new("name", "warning", "time", "output", [], "failure_type")
      expect(tr.name).to eq("name")
      expect(tr.failure_type).to eq("failure_type")
    end
  end
  context 'when constructing a warning testresult' do
    it 'should return warning status accordingly' do
      tr = TestResult.new("name", "warning", "time", "output", [], "failure_type")
      expect(tr.warning).to be_truthy
    end
    it 'should be very sensitive about warning status' do
      tr = TestResult.new("name", "Warning", "time", "output", [], "failure_type")
      expect(tr.warning).to be_falsey
    end
    it 'should be considering passing' do
      tr = TestResult.new("name", "warning", "time", "output", [], "failure_type")
      expect(tr.passed).to be_truthy
    end
  end
  context 'when inspecting a testresult' do
    it 'should return a hash with at least a few specific things' do
      tr = TestResult.new("name", "warning", "time", "output", ["a"], "failure_type")
      inspection = tr.inspect
      expect(inspection).to be_an_instance_of(Hash)
      expect(inspection).to have_key(:name)
      expect(inspection).to have_key(:parsed_errors)
    end
  end
end

describe 'TestMessage Testing' do
  context 'when inspecting a testmessage' do
    it 'should return a hash with at least a few specific things' do
      tm = TestMessage.new("name", "message")
      inspection = tm.inspect
      expect(inspection).to be_an_instance_of(Hash)
      expect(inspection).to have_key(:name)
      expect(inspection).to have_key(:message)
    end
  end
end