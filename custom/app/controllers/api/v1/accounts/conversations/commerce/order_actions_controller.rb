# Order actions on one of the conversation's linked customer's orders (docs/commerce/28-commerce-actions-architecture.md).
# Anyone who can view the conversation can ask what is possible; performing needs Commerce::ActionPolicy. Only active
# stores of the conversation's account, of a provider the installation offers, are reachable.
#
#   GET  .../conversations/:conversation_id/commerce/stores/:store_id/orders/:order_id/actions   availability, read now
#   POST .../conversations/:conversation_id/commerce/stores/:store_id/orders/:order_id/actions   request one action:
#        { action_type, version, idempotency_key: "commerce-action:<uuid>", params: { … } } → 202 + the run
class Api::V1::Accounts::Conversations::Commerce::OrderActionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_commerce_enabled

  rescue_from ::Commerce::Error do |error|
    if error.code == 'RATE_LIMITED' && error.reason.present?
      response.headers['Retry-After'] = error.reason
      render json: { error: { code: error.code, retry_after: error.reason.to_i } }, status: :too_many_requests
    else
      render json: { error: error.as_json }, status: :unprocessable_entity
    end
  end

  def show
    render json: order_actions.availability(params[:order_id].to_s)
  end

  def create
    run = order_actions.request(params[:action_type].to_s, order_id: params[:order_id].to_s, version: params[:version].to_s,
                                                           idempotency_key: params[:idempotency_key].to_s, params: action_params)
    render json: run, status: :accepted
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def order_actions
    store = Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled).find(params[:store_id])
    ::Commerce::OrderActions.new(store: store, contact_id: @conversation.contact_id, conversation_id: @conversation.id, user: Current.user,
                                 account_user: Current.account_user)
  end

  def action_params
    value = params[:params]
    value.is_a?(ActionController::Parameters) ? value.permit(:target_status, :reason, :restock, :amount, :currency) : {}
  end
end
