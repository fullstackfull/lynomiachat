# The state of an order action requested from this conversation (Commerce::ActionRun), for the agent's browser to follow
# until the store has answered.
#
#   GET .../conversations/:conversation_id/commerce/action_runs/:id
class Api::V1::Accounts::Conversations::Commerce::ActionRunsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_commerce_enabled

  def show
    render json: ::Commerce::ActionRun.order_actions.where(account_id: Current.account.id, conversation_id: @conversation.id).find(params[:id])
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end
end
