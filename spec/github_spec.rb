require 'octokit'
require 'rspec'
require_relative '../lib/github'

class DummyResponse
  def headers
    t = Time.now + 5 # 5 seconds in the future
    t.utc
    rate_limit_reset_time = t.to_i
    {
        'x-ratelimit-limit' => '5000',
        'x-ratelimit-remaining' => '4999',
        'x-ratelimit-reset' => rate_limit_reset_time
    }
  end
end

class DummyClient
  def initialize
    @counter = 0
  end
  def last_response
    return DummyResponse.new
  end
end

def dummy_function
  raise Octokit::TooManyRequests
end

describe 'GitHub Testing' do
  context 'when calling github_query' do
    it 'should yield whatever pass in for quick results' do
      quick_response = github_query(nil) { 3.14 }
      expect(quick_response).to eql 3.14
    end
    it 'should eventually fail if rate limit persists' do
      c = DummyClient.new
      expect{ github_query(c, 1) { dummy_function } }.to raise_error Octokit::TooManyRequests
    end
  end
  context 'when calling github_check_rate_limit' do
    it 'should calculate proper rate limits' do
      t = Time.now + 3600 # 1 hour in the future
      t.utc
      rate_limit_reset_time = t.to_i
      rate_limit_hash = {
        'x-ratelimit-limit' => '5000',
        'x-ratelimit-remaining' => '4999',
        'x-ratelimit-reset' => rate_limit_reset_time
      }
      response = github_check_rate_limit(rate_limit_hash)
      expect(response).to be_between(3500, 3600)
    end
  end
end
