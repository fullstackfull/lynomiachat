# WooCommerce webhook deliveries for Lynomia Commerce: POST /webhooks/woocommerce/:store_id, the delivery URL of the
# webhooks Lynomia created in the store (Commerce::Providers::Woocommerce#register_webhooks).
#
# Authenticate, deduplicate, queue: the signature over the raw body is checked with the store's own secret before anything
# is parsed. An unsigned or badly signed delivery (WooCommerce's unsigned creation ping included), a store that is not
# connected, or one with no webhook secret gets 401. Topics Lynomia did not subscribe to are acknowledged and dropped.
class Webhooks::WoocommerceController < ActionController::API
  def create
    body = request.raw_post
    store = Commerce::Store.where.not(status: :disconnected).find_by(provider: 'woocommerce', id: request.path_parameters[:store_id].to_s)
    unless Commerce::Woocommerce::Webhook.authentic?(store, body, request.headers['X-WC-Webhook-Signature'])
      Commerce::Metrics.event('commerce.webhook.rejected', provider: 'woocommerce', store_id: store&.id)
      return head :unauthorized
    end

    # The signature just proved this delivery came from this store, which is a fact about the store's health
    # whatever the topic is -- recorded here rather than at #enqueue so a topic Lynomia does not subscribe to
    # still counts as the provider talking (docs/product-refinement/09-commerce-operations.md §webhooks).
    Commerce::StoreHealthRecorder.webhook_received(store)
    enqueue(store, body) if Commerce::Providers::Woocommerce::WEBHOOK_TOPICS.include?(request.headers['X-WC-Webhook-Topic'])
    head :ok
  end

  private

  def enqueue(store, body)
    Commerce::Woocommerce::Webhook.enqueue(store, request.headers['X-WC-Webhook-Delivery-ID'], body)
  end
end
