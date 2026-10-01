# Redis cache for store reads. An entry is fresh for 120 s; after that it is refreshed, and when the store is
# unavailable an entry up to 24 h old is served as stale (with the time it was fetched and the error code) instead of
# being shown as live data. Only provider-neutral JSON is stored, never credentials.
#
# Keys: COMMERCE::V1::ACCOUNT::<account_id>::STORE::<store_id>::<kind>::<HMAC of the customer or contact identifier>
# (the identifier can be an email or phone, so it never appears in a key).
class Commerce::Cache
  FRESH_FOR = 120.seconds
  KEEP_FOR = 24.hours
  STALE_FALLBACK_CODES = %w[STORE_UNAVAILABLE TIMEOUT RATE_LIMITED INVALID_RESPONSE].freeze

  Result = Data.define(:value, :fetched_at, :stale, :error)

  # `force` reads the store even when the entry is fresh (an agent's Refresh); the entry stays the fallback if it fails.
  def self.fetch(store, kind, identifier, force: false)
    key = key(store, kind, identifier)
    entry = read(key)
    hit = !force && fresh?(entry)
    Commerce::Metrics.event(hit ? 'commerce.cache.hit' : 'commerce.cache.miss', store_id: store.id, kind: kind, forced: force)
    return Result.new(value: entry['value'], fetched_at: entry['fetched_at'], stale: false, error: nil) if hit

    write(key, yield.as_json)
  rescue Commerce::Error => e
    raise unless entry && STALE_FALLBACK_CODES.include?(e.code)

    Result.new(value: entry['value'], fetched_at: entry['fetched_at'], stale: true, error: e.code)
  end

  # Marks one entry outdated (a store event says it changed): its next read goes to the store, and the entry stays the
  # stale fallback, with the time it was fetched, if the store cannot answer then.
  def self.invalidate(store, kind, identifier)
    outdate(key(store, kind, identifier))
  end

  def self.purge(store)
    delete_matching("#{prefix(store)}::*")
  end

  # Marks every entry of one kind in the store outdated (an order event that names no customer: every customer's orders).
  def self.invalidate_all(store, kind)
    matching("#{prefix(store)}::#{kind.to_s.upcase}::*").each { |key| outdate(key) }
  end

  def self.matching(pattern)
    keys = []
    Redis::Alfred.scan_each(match: pattern) { |key| keys << key }
    keys
  end

  def self.delete_matching(pattern)
    matching(pattern).each { |key| Redis::Alfred.delete(key) }
  end

  def self.outdate(key)
    entry = read(key)
    Redis::Alfred.with { |conn| conn.set(key, entry.merge('outdated' => true).to_json, keepttl: true) } if entry
  end

  def self.key(store, kind, identifier)
    "#{prefix(store)}::#{kind.to_s.upcase}::#{OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, identifier.to_s)}"
  end

  def self.prefix(store)
    "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}"
  end

  def self.read(key) = JSON.parse(Redis::Alfred.get(key) || 'null')

  def self.write(key, value)
    fetched_at = Time.current.utc.iso8601
    Redis::Alfred.setex(key, { value: value, fetched_at: fetched_at }.to_json, KEEP_FOR)
    Result.new(value: value, fetched_at: fetched_at, stale: false, error: nil)
  end

  def self.fresh?(entry)
    entry.present? && !entry['outdated'] && Time.iso8601(entry['fetched_at']) > FRESH_FOR.ago
  end

  private_class_method :key, :prefix, :read, :write, :fresh?, :matching, :delete_matching, :outdate
end
