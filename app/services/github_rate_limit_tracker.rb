class GithubRateLimitTracker
  class RateLimitExceeded < StandardError; end

  def self.track_request(response)
    new.track_request(response)
  end

  def track_request(response)
    remaining = response['X-RateLimit-Remaining'].to_i
    limit = response['X-RateLimit-Limit'].to_i
    reset = response['X-RateLimit-Reset'].to_i

    percentage_used = ((limit - remaining).to_f / limit) * 100

    log_rate_limit_state(remaining, limit, reset, percentage_used)
    store_rate_limit_state(remaining, limit, reset)

    if remaining < (limit * 0.1).to_i
      raise RateLimitExceeded, "Rate limit approaching: #{remaining}/#{limit} remaining, resets at #{Time.at(reset)}"
    end

    { remaining: remaining, limit: limit, reset: reset, percentage_used: percentage_used }
  end

  private

  def log_rate_limit_state(remaining, limit, reset, percentage_used)
    if remaining < (limit * 0.2).to_i
      Rails.logger.warn("⚠️ RATE LIMIT WARNING: #{remaining}/#{limit} requests remaining (#{percentage_used.round(1)}% used) - Resets at #{Time.at(reset)}")
    elsif remaining < (limit * 0.5).to_i
      Rails.logger.info("📊 Rate limit: #{remaining}/#{limit} remaining (#{percentage_used.round(1)}% used)")
    end
  end

  def store_rate_limit_state(remaining, limit, reset)
    if defined?(Redis)
      begin
        Rails.cache.write('github:rate_limit:remaining', remaining, expires_in: 1.hour)
        Rails.cache.write('github:rate_limit:limit', limit, expires_in: 1.hour)
        Rails.cache.write('github:rate_limit:reset', reset, expires_in: 1.hour)
      rescue => e
        Rails.logger.debug("Could not store rate limit state in cache: #{e.message}")
      end
    end
  end
end