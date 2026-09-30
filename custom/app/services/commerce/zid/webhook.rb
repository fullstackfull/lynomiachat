# Receiving Zid webhook deliveries (docs/commerce/15-zid-webhook-security.md). This is HTTP Basic Authentication, not a
# signature: each store has its own random username and password (Commerce::Zid::Webhooks), stored encrypted, and Zid
# sends them with every delivery. Both are compared in constant time, and nothing in a body is read before they match.
#
# An authenticated delivery is queued once: an identical body for the same store within DEDUP_TTL is a redelivery and is
# acknowledged without being queued again. The body is encrypted for Sidekiq, which keeps job arguments in Redis in
# plaintext, because an order carries the customer's name, email and phone.
module Commerce::Zid::Webhook
  DEDUP_TTL = 1.day
  PURPOSE = :commerce_zid_webhook

  def self.authorized?(store, username, password)
    expected_username, expected_password = store&.credentials&.values_at('webhook_username', 'webhook_password')
    return false unless [expected_username, expected_password, username, password].all?(String)

    ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &
      ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
  end

  def self.enqueue(store, raw_body)
    key = "COMMERCE::ZID::WEBHOOK::#{store.id}::#{Digest::SHA256.hexdigest(raw_body)}"
    return unless Redis::Alfred.set(key, 1, nx: true, ex: DEDUP_TTL.to_i)

    begin
      Commerce::Zid::WebhookJob.perform_later(store.id, encryptor.encrypt_and_sign(raw_body, purpose: PURPOSE))
    rescue StandardError
      Redis::Alfred.delete(key)
      raise
    end
  end

  def self.unseal(sealed)
    JSON.parse(encryptor.decrypt_and_verify(sealed, purpose: PURPOSE))
  end

  def self.encryptor
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key(PURPOSE.to_s, 32))
  end
  private_class_method :encryptor
end
