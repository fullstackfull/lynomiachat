# Prepares a recovery message for one of the conversation contact's abandoned carts (Commerce::RecoveryMessages): the
# answer fills the reply box, the agent sends it. Anyone who can see the conversation can prepare one; overriding the
# cooldown is for administrators.
#
#   POST .../conversations/:conversation_id/commerce/stores/:store_id/carts/:cart_id/recovery { override_cooldown: false }
class Api::V1::Accounts::Conversations::Commerce::RecoveriesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_commerce_enabled

  rescue_from ::Commerce::Error do |error|
    status = error.code == 'RATE_LIMITED' ? :too_many_requests : :unprocessable_entity
    response.headers['Retry-After'] = error.reason if error.code == 'RATE_LIMITED'
    render json: { error: error.as_json }, status: status
  end

  def create
    store = Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled).find(params[:store_id])
    recovery = ::Commerce::RecoveryMessages.new(store: store, conversation: @conversation, user: Current.user, account_user: Current.account_user)
    render json: recovery.prepare(params[:cart_id], override_cooldown: params[:override_cooldown] == true), status: :created
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end
end
