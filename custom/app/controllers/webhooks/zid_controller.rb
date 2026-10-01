# Zid webhook deliveries for Lynomia Commerce: POST /webhooks/zid/:store_id, the target URL each connected Zid store's
# subscriptions were created with (Commerce::Zid::Webhooks).
#
# Authenticate, deduplicate, queue: this request only checks the store's Basic Auth credentials and queues the body. A
# delivery without credentials, with a wrong username or password, or for a store that is not connected gets 401 and is
# never parsed. Cached data is invalidated in Commerce::Zid::WebhookJob.
class Webhooks::ZidController < ActionController::API
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  def create
    # The path only: `params` would parse the JSON body before the credentials are checked.
    store_id = request.path_parameters[:store_id].to_s
    store = Commerce::Store.where.not(status: :disconnected).find_by(provider: 'zid', external_store_id: store_id)
    authorized = authenticate_with_http_basic { |username, password| Commerce::Zid::Webhook.authorized?(store, username, password) }
    unless authorized
      Commerce::Metrics.event('commerce.webhook.rejected', provider: 'zid', store_id: store&.id)
      return head :unauthorized
    end

    Commerce::Zid::Webhook.enqueue(store, request.raw_post)
    head :ok
  end
end
