# Order search from the conversation's Commerce section (docs/commerce/25-customer-360.md §order search): the orders
# with the number the customer quotes, in one store or every active store of the account. The same people who can see
# the conversation's Commerce section can search. Rate-limited per agent (SEARCH_LIMIT per minute); each search is
# audited with its number and result counts.
#
#   GET .../conversations/:conversation_id/commerce/orders?number=1001[&store_id=:id]
class Api::V1::Accounts::Conversations::Commerce::OrdersController < Api::V1::Accounts::Conversations::BaseController
  NUMBER = /\A#?(\d{1,20})\z/
  SEARCH_LIMIT = 10

  before_action :ensure_commerce_enabled, :throttle

  rescue_from ::Commerce::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def index
    number = params[:number].to_s.strip[NUMBER, 1]
    raise ::Commerce::Error, 'INVALID_QUERY' if number.nil?

    stores = params[:store_id].present? ? [active_stores.find(params[:store_id])] : active_stores.order(:created_at).to_a
    result = ::Commerce::OrderSearch.new(stores: stores, number: number).call
    audit(number: number, stores: stores.size, orders: result[:orders].size)
    render json: result
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def active_stores
    Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled)
  end

  def audit(changes)
    ::Commerce::AuditTrail.record('commerce.orders_searched', auditable: Current.account, user: Current.user, changes: changes)
  end

  def throttle
    key = "COMMERCE::ORDER_SEARCH::ACCOUNT::#{Current.account.id}::USER::#{Current.user.id}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.minute.to_i) if count == 1
    return if count <= SEARCH_LIMIT

    retry_after = [Redis::Alfred.ttl(key).to_i, 1].max
    response.headers['Retry-After'] = retry_after.to_s
    render json: { error: { code: 'RATE_LIMITED', retry_after: retry_after } }, status: :too_many_requests
  end
end
