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

  def self.fetch(store, kind, identifier)
    key = key(store, kind, identifier)
    entry = JSON.parse(Redis::Alfred.get(key) || 'null')
    return Result.new(value: entry['value'], fetched_at: entry['fetched_at'], stale: false, error: nil) if fresh?(entry)

    value = yield.as_json
    fetched_at = Time.current.utc.iso8601
    Redis::Alfred.setex(key, { value: value, fetched_at: fetched_at }.to_json, KEEP_FOR)
    Result.new(value: value, fetched_at: fetched_at, stale: false, error: nil)
  rescue Commerce::Error => e
    raise unless entry && STALE_FALLBACK_CODES.include?(e.code)

    Result.new(value: entry['value'], fetched_at: entry['fetched_at'], stale: true, error: e.code)
  end

  # Drops one entry, so its next read goes to the store (a Zid order webhook for the customer's cached orders).
  def self.invalidate(store, kind, identifier)
    Redis::Alfred.delete(key(store, kind, identifier))
  end

  def self.purge(store)
    delete_matching("#{prefix(store)}::*")
  end

  # Drops every entry of one kind in the store (an order event that names no customer drops every customer's orders).
  def self.invalidate_all(store, kind)
    delete_matching("#{prefix(store)}::#{kind.to_s.upcase}::*")
  end

  def self.delete_matching(pattern)
    keys = []
    Redis::Alfred.scan_each(match: pattern) { |key| keys << key }
    keys.each { |key| Redis::Alfred.delete(key) }
  end

  def self.key(store, kind, identifier)
    "#{prefix(store)}::#{kind.to_s.upcase}::#{OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, identifier.to_s)}"
  end

  def self.prefix(store)
    "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}"
  end

  def self.fresh?(entry)
    entry.present? && Time.iso8601(entry['fetched_at']) > FRESH_FOR.ago
  end

  private_class_method :key, :prefix, :fresh?, :delete_matching
end
