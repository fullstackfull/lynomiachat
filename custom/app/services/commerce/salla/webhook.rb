# Salla app events (docs/commerce/12-salla-security.md). Salla signs every delivery with the app's webhook secret:
# `X-Salla-Security-Strategy: Signature` and `X-Salla-Signature: hex(HMAC-SHA256(raw body, secret))`. Nothing in a body is
# read before its signature checks out.
#
# A verified body is queued once (Salla resends an event up to three times) and encrypted, because it can carry OAuth
# tokens: Sidekiq keeps job arguments in Redis in plaintext.
module Commerce::Salla::Webhook
  DEDUP_TTL = 3.days
  PURPOSE = :commerce_salla_webhook

  def self.verified?(raw_body, strategy:, signature:, secret:)
    return false unless strategy == 'Signature' && signature.is_a?(String)

    ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body), signature)
  end

  def self.enqueue(raw_body)
    key = "COMMERCE::SALLA::WEBHOOK::#{Digest::SHA256.hexdigest(raw_body)}"
    return Commerce::Metrics.event('commerce.webhook.duplicate', provider: 'salla') unless Redis::Alfred.set(key, 1, nx: true, ex: DEDUP_TTL)

    begin
      Commerce::Salla::WebhookJob.perform_later(encryptor.encrypt_and_sign(raw_body, purpose: PURPOSE))
      Commerce::Metrics.event('commerce.webhook.accepted', provider: 'salla')
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
