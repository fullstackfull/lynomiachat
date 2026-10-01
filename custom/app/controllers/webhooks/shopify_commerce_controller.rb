# Webhook deliveries of the Lynomia Commerce Shopify app: POST /webhooks/shopify_commerce, the URI of the app's
# app-specific subscriptions (Commerce::Shopify::Webhook). The legacy integration's /webhooks/shopify is separate.
#
# Authenticate, deduplicate, queue: this request checks Shopify's HMAC over the raw body before anything is parsed (401
# otherwise), then queues the delivery once per X-Shopify-Webhook-Id, the id Shopify keeps across retries of a delivery.
# The privacy topics and app/uninstalled are processed whatever the provider switch says. Nothing else happens here.
class Webhooks::ShopifyCommerceController < ActionController::API
  def create
    body = request.raw_post
    unless Commerce::Shopify::Webhook.authentic?(body, request.headers['X-Shopify-Hmac-Sha256'])
      Commerce::Metrics.event('commerce.webhook.rejected', provider: 'shopify')
      return head :unauthorized
    end

    shop = request.headers['X-Shopify-Shop-Domain']
    webhook_id = request.headers['X-Shopify-Webhook-Id']
    return head :bad_request unless webhook_id.present? && ::Shopify::ShopDomain.valid?(shop)

    enqueue(request.headers['X-Shopify-Topic'], ::Shopify::ShopDomain.normalize(shop), webhook_id, body)
    head :ok
  end

  private

  # A topic the app does not subscribe to is acknowledged and dropped.
  def enqueue(topic, shop, webhook_id, body)
    return unless Commerce::Shopify::Webhook::TOPICS.include?(topic)

    Commerce::WebhookQueue.enqueue('shopify', Digest::SHA256.hexdigest(webhook_id), Commerce::Shopify::WebhookJob, topic, shop,
                                   request.headers['X-Shopify-Triggered-At'], body: body)
  end
end
