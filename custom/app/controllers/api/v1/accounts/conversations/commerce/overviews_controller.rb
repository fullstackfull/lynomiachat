# Customer 360 for the conversation's contact (`lynomia_commerce` accounts): every connected store's view of the contact,
# aggregated (Commerce::Customer360). The same people who can see the conversation's per-store Commerce section see it.
#
#   GET .../conversations/:conversation_id/commerce/overview
class Api::V1::Accounts::Conversations::Commerce::OverviewsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_commerce_enabled

  def show
    render json: ::Commerce::Customer360.new(conversation: @conversation, user: Current.user).call
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end
end
