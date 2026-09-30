# A Salla merchant's installation state and tokens only change under this lock, so installation events and token
# refreshes never interleave (a refresh token is single-use). Owner-safe: only the holder releases it, and it expires
# on its own if the holder dies. TTL is well above the longest HTTP call made while holding it (Commerce::HttpClient
# bounds one to about 21 s).
module Commerce::Salla::MerchantLock
  TTL = 60
  WAIT = 10
  POLL = 0.1

  def self.with(merchant_id, wait: WAIT)
    key = "COMMERCE::SALLA::MERCHANT::#{merchant_id}::LOCK"
    owner = SecureRandom.hex(16)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
    until Redis::Alfred.set(key, owner, nx: true, ex: TTL)
      raise Commerce::Error.new('STORE_UNAVAILABLE', reason: 'salla_busy') if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep POLL
    end

    begin
      yield
    ensure
      Redis::Alfred.delete_if_equals(key, owner)
    end
  end
end
