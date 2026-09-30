# Rate-limit backoff for platform APIs whose limits are per store (Salla, Zid). Once a provider answers 429 or reports
# no requests left, further calls for that store fail fast with RATE_LIMITED until its reset time (at most MAX seconds),
# so the panel serves its cache instead of adding to the limit.
module Commerce::Backoff
  MAX = 60

  def self.check!(key)
    raise Commerce::Error, 'RATE_LIMITED' if Redis::Alfred.exists?(key)
  end

  # `limits` is Commerce::HttpClient#rate_limit of the last response.
  def self.record(key, limits)
    return if limits.nil? || !(limits[:retry_after] || limits[:remaining]&.zero?)

    wait = limits[:retry_after] || (limits[:reset].to_i - Time.now.to_i)
    Redis::Alfred.set(key, 1, ex: wait.clamp(1, MAX))
  end
end
