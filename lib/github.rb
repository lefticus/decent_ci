
def github_check_ratelimit(headers)
  ratelimit = headers["x-ratelimit-limit"].to_i
  ratelimit_remaining = headers["x-ratelimit-remaining"].to_i
  ratelimit_reset = headers["x-ratelimit-reset"].to_i
  ratelimit_start = ratelimit_reset - 60 * 60 # 60 minutes in seconds

  t = Time.now
  t.utc
  ratelimit_current_time = t.to_i

  ratelimit_burnrate_queries_per_second = (ratelimit - ratelimit_remaining).to_f / (ratelimit_current_time - ratelimit_start).to_f
  ratelimit_burnrate_queries_per_hour = ratelimit_burnrate_queries_per_second * 60 * 60

  $logger.info("ratelimit #{ratelimit}")
  $logger.info("ratelimit_remaining #{ratelimit_remaining}")
  $logger.info("ratelimit_reset #{ratelimit_reset}")
  $logger.info("ratelimit_start #{ratelimit_start}")
  $logger.info("ratelimit_current_time #{ratelimit_current_time}")
  $logger.info("ratelimit_burnrate_queries_per_hour #{ratelimit_burnrate_queries_per_hour}")

  return ratelimit_reset - ratelimit_current_time # return seconds until next reset
end

def github_query(client, num_retries = 2)
  count = 0
  while true
    begin
      return yield
    rescue Octokit::TooManyRequests => e
      count += 1

      if count > num_retries
        $logger.error("Rate limit has been exceeded retries exhausted, re-throwing error")
        raise
      end
      time_to_sleep = github_check_ratelimit(client.last_response.headers)
      $logger.info("Rate limit has been exceeded, ratelimit will be reset in: #{time_to_sleep}s")
      time_to_sleep += Random.rand(10)
      $logger.info("Rate limit has been exceeded, sleeping for: #{time_to_sleep}s")

      if time_to_sleep > 0
        sleep(time_to_sleep)
      end
    end
  end
end

