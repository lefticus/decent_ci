# frozen_string_literal: true

def github_check_rate_limit(headers)
  rate_limit = headers['x-ratelimit-limit'].to_i
  rate_limit_remaining = headers['x-ratelimit-remaining'].to_i
  rate_limit_reset = headers['x-ratelimit-reset'].to_i
  rate_limit_start = rate_limit_reset - 60 * 60 # 60 minutes in seconds

  t = Time.now
  t.utc
  rate_limit_current_time = t.to_i

  burn_rate_queries_per_second = (rate_limit - rate_limit_remaining).to_f / (rate_limit_current_time - rate_limit_start).to_f
  burn_rate_queries_per_hour = burn_rate_queries_per_second * 60 * 60

  $logger.info("ratelimit #{rate_limit}")
  $logger.info("ratelimit_remaining #{rate_limit_remaining}")
  $logger.info("ratelimit_reset #{rate_limit_reset}")
  $logger.info("ratelimit_start #{rate_limit_start}")
  $logger.info("ratelimit_current_time #{rate_limit_current_time}")
  $logger.info("ratelimit_burn_rate_queries_per_hour #{burn_rate_queries_per_hour}")

  rate_limit_reset - rate_limit_current_time # return seconds until next reset
end

def github_query(client, num_retries = 2)
  count = 0
  loop do
    begin
      return yield
    rescue Octokit::TooManyRequests
      count += 1

      if count > num_retries
        $logger.error('Rate limit has been exceeded retries exhausted, re-throwing error')
        raise
      end
      time_to_sleep = github_check_rate_limit(client.last_response.headers) + 3 # add a little buffer to the delay time
      $logger.info("Rate limit has been exceeded, rate limit will be reset in: #{time_to_sleep}s")
      $logger.info("Rate limit has been exceeded, sleeping for: #{time_to_sleep}s")

      sleep(time_to_sleep) if time_to_sleep.positive?
    end
  end
end
