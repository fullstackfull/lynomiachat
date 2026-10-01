# Queues an authenticated provider webhook delivery (WooCommerce, Zid, Shopify): once, and with its body encrypted.
#
# The caller has already authenticated the delivery; nothing heavy happens in the request. A delivery whose dedup key was
# seen within DEDUP_TTL is a redelivery and is acknowledged without being queued again; the key expires, so a key is
# never remembered forever. The body is encrypted for Sidekiq, which keeps job arguments in Redis in plaintext, because
# order and customer payloads carry names, emails and phones.
module Commerce::WebhookQueue
  DEDUP_TTL = 1.day

  # Queues `job` with `args` and the sealed body, unless `dedup_key` was queued within DEDUP_TTL.
  def self.enqueue(provider, dedup_key, job, *, body:)
    key = "COMMERCE::#{provider.upcase}::WEBHOOK::#{dedup_key}"
    unless Redis::Alfred.set(key, 1, nx: true, ex: DEDUP_TTL.to_i)
      Commerce::Metrics.event('commerce.webhook.duplicate', provider: provider)
      return
    end

    begin
      job.perform_later(*, encryptor(provider).encrypt_and_sign(body, purpose: purpose(provider)))
      Commerce::Metrics.event('commerce.webhook.accepted', provider: provider)
    rescue StandardError
      Redis::Alfred.delete(key)
      raise
    end
  end

  # The parsed body of a delivery sealed by .enqueue.
  def self.unseal(provider, sealed)
    JSON.parse(encryptor(provider).decrypt_and_verify(sealed, purpose: purpose(provider)))
  end

  def self.purpose(provider) = "commerce_#{provider}_webhook"

  def self.encryptor(provider)
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key(purpose(provider), 32))
  end
  private_class_method :purpose, :encryptor
end
