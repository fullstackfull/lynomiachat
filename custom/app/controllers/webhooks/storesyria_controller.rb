# Store Syria commerce event deliveries: POST /webhooks/storesyria.
#
# Authenticate, deduplicate, queue -- the same three steps as every other provider's receiver,
# and in the same order: the signature over the raw body is checked before anything is parsed.
# Unlike the others the path carries no store id, because Store Syria cannot know Lynomia's row
# id; the store is named in a header and the signature is what proves the name.
class Webhooks::StoresyriaController < ActionController::API
  def create
    body = request.raw_post
    store = Commerce::Storesyria::Webhook.store_for(request.headers['X-Storesyria-Store'])
    unless Commerce::Storesyria::Webhook.authentic?(store, body, request.headers['X-Storesyria-Signature'],
                                                    request.headers['X-Storesyria-Timestamp'])
      Commerce::Metrics.event('commerce.webhook.rejected', provider: 'storesyria', store_id: store&.id)
      return head :unauthorized
    end

    # The signature proved this delivery came from this store, which is a fact about the store's
    # health whatever the event turns out to be.
    Commerce::StoreHealthRecorder.webhook_received(store)
    Commerce::Storesyria::Webhook.enqueue(store, request.headers['X-Storesyria-Delivery'], body)
    head :ok
  end
end
