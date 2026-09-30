# A store's authorization state and tokens only change under this lock, so authorizations, token refreshes and
# installation events never interleave. It is keyed by the provider's own store id (Salla merchant, Zid store), so it
# holds across Lynomia accounts and processes. Owner-safe: only the holder releases it, and it expires on its own if the
# holder dies. TTL is well above the longest HTTP call made while holding it (Commerce::HttpClient bounds one to about
# 21 s).
module Commerce::StoreLock
  TTL = 60
  WAIT = 10
  POLL = 0.1

  def self.with(provider, external_store_id, wait: WAIT)
    key = "COMMERCE::#{provider.upcase}::MERCHANT::#{external_store_id}::LOCK"
    owner = SecureRandom.hex(16)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
    until Redis::Alfred.set(key, owner, nx: true, ex: TTL)
      raise Commerce::Error.new('STORE_UNAVAILABLE', reason: "#{provider}_busy") if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep POLL
    end

    begin
      yield
    ensure
      Redis::Alfred.delete_if_equals(key, owner)
    end
  end
end
