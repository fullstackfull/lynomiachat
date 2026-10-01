# Receiving WooCommerce webhook deliveries (docs/commerce/26-realtime-security.md). WooCommerce signs each delivery with
# the webhook's secret: `X-WC-Webhook-Signature: base64(HMAC-SHA256(raw body, secret))`. Each store has its own random
# secret (Commerce::Providers::Woocommerce#register_webhooks), stored encrypted with its credentials, so a delivery signed
# for one store is refused at every other store's URL. Nothing in a body is read before the signature checks out.
#
# An authentic delivery is queued once through Commerce::WebhookQueue, by WooCommerce's delivery id (or the body when a
# delivery has none).
module Commerce::Woocommerce::Webhook
  def self.authentic?(store, raw_body, signature)
    secret = store&.credentials&.dig('webhook_secret')
    return false unless secret.is_a?(String) && secret.present? && signature.is_a?(String)

    ActiveSupport::SecurityUtils.secure_compare(Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, raw_body)), signature)
  end

  def self.enqueue(store, delivery_id, raw_body)
    Commerce::WebhookQueue.enqueue('woocommerce', "#{store.id}::#{Digest::SHA256.hexdigest(delivery_id.presence || raw_body)}",
                                   Commerce::Woocommerce::WebhookJob, store.id, body: raw_body)
  end
end
