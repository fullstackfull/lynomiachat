# One-time codes that prove which Lynomia account a Salla installation belongs to
# (docs/commerce/10-salla-install-correlation.md).
#
# An account administrator creates a code in Lynomia; it is shown once and only its HMAC is kept. The merchant enters it
# in the Lynomia app's settings in their Salla dashboard, and Salla delivers it, signed, in `app.settings.updated` for
# that merchant. A code works once and for one hour; a new code replaces the account's previous one. The account's
# progress (waiting → claimed → connected, or conflict) is what the settings page polls.
class Commerce::Salla::ConnectionCode
  TTL = 1.hour
  PROGRESS_TTL = 1.day
  # 32 symbols without 0/O/1/I, so 16 of them are 80 random bits.
  ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.freeze
  LENGTH = 16

  def self.create(account:, user:)
    install_url = Commerce::Salla::Config.install_url
    code = Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
    expires_at = TTL.from_now.utc.iso8601
    code_digest = digest(code)
    previous = progress(account.id)
    Redis::Alfred.delete(code_key(previous['digest'])) if previous
    Redis::Alfred.setex(code_key(code_digest), { account_id: account.id, user_id: user.id }.to_json, TTL)
    save_progress(account.id, 'status' => 'waiting', 'digest' => code_digest, 'expires_at' => expires_at)
    Commerce::AuditTrail.record('commerce.salla.connect_started', auditable: account, user: user)
    { code: code.scan(/.{4}/).join('-'), expires_at: expires_at, install_url: install_url }
  end

  # { 'account_id', 'user_id' } the code was created for, or nil. A code is deleted as it is read, so it works once.
  # The merchant types it, so case, spaces and dashes do not matter.
  def self.redeem(raw_code)
    key = code_key(digest(raw_code.upcase.delete('^A-Z0-9')))
    value, = Redis::Alfred.with do |conn|
      conn.multi do |transaction|
        transaction.get(key)
        transaction.del(key)
      end
    end
    return if value.nil?

    JSON.parse(value).tap { |attempt| finish(attempt['account_id'], 'claimed') }
  end

  def self.finish(account_id, status, store_id: nil)
    current = progress(account_id)
    save_progress(account_id, current.merge('status' => status, 'store_id' => store_id).compact) if current
  end

  # What the settings page shows: none | waiting | expired | claimed | connected | conflict | limit_reached.
  def self.status(account)
    current = progress(account.id)
    return { status: 'none' } if current.nil?

    status = current['status'] == 'waiting' && Time.iso8601(current['expires_at']).past? ? 'expired' : current['status']
    { status: status, expires_at: current['expires_at'], store_id: current['store_id'] }.compact
  end

  def self.digest(code)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key('commerce_salla_connection_code'), code)
  end

  def self.code_key(digest) = "COMMERCE::SALLA::CONNECTION_CODE::#{digest}"

  def self.progress_key(account_id) = "COMMERCE::SALLA::CONNECTION::ACCOUNT::#{account_id}"

  def self.progress(account_id)
    JSON.parse(Redis::Alfred.get(progress_key(account_id)) || 'null')
  end

  def self.save_progress(account_id, progress)
    Redis::Alfred.setex(progress_key(account_id), progress.to_json, PROGRESS_TTL)
  end

  private_class_method :digest, :code_key, :progress_key, :progress, :save_progress
end
