# An agent's Refresh in the conversation's Commerce section: the current view is read again from the stores now, even
# when its cached data is still fresh. Rate-limited per contact and view (COOLDOWN, shared by everyone viewing it), and
# the stores' own rate-limit backoff still applies: a refused store answers with its last data, marked stale.
#
#   POST .../conversations/:conversation_id/commerce/refresh              Customer 360 (Commerce::Customer360)
#   POST .../conversations/:conversation_id/commerce/refresh?store_id=:id  one store's view (Commerce::ConversationPanel)
class Api::V1::Accounts::Conversations::Commerce::RefreshesController < Api::V1::Accounts::Conversations::BaseController
  COOLDOWN = 30.seconds

  before_action :ensure_commerce_enabled

  def create
    store = active_stores.find(params[:store_id]) if params[:store_id].present?
    key = cooldown_key(store)
    return cooling_down(key) unless Redis::Alfred.set(key, 1, nx: true, ex: COOLDOWN.to_i)

    render json: if store
                   ::Commerce::ConversationPanel.new(store: store, conversation: @conversation, user: Current.user).show(force: true)
                 else
                   ::Commerce::Customer360.new(conversation: @conversation, user: Current.user, force: true).call
                 end
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def active_stores
    Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled)
  end

  def cooldown_key(store)
    "COMMERCE::REFRESH_REQUEST::ACCOUNT::#{Current.account.id}::CONTACT::#{@conversation.contact_id}::#{store ? "STORE::#{store.id}" : 'OVERVIEW'}"
  end

  def cooling_down(key)
    retry_after = [Redis::Alfred.ttl(key).to_i, 1].max
    response.headers['Retry-After'] = retry_after.to_s
    render json: { error: { code: 'RATE_LIMITED', retry_after: retry_after } }, status: :too_many_requests
  end
end
