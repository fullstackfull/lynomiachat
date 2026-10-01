# The conversation's Commerce section (`lynomia_commerce` accounts). Anyone who can view the conversation can see its
# contact's store data and link or unlink the store customer (like editing the contact); only active stores of the
# conversation's account, of a provider the installation offers, are reachable.
#
#   GET    .../conversations/:conversation_id/commerce/stores                 active stores + whether the contact is linked
#   GET    .../conversations/:conversation_id/commerce/stores/:id             panel: link, candidates, latest orders
#   GET    .../conversations/:conversation_id/commerce/stores/:id/customers   search by exact email or international phone
#   POST   .../conversations/:conversation_id/commerce/stores/:id/link        link a candidate (signed token)
#   DELETE .../conversations/:conversation_id/commerce/stores/:id/link        remove the link
class Api::V1::Accounts::Conversations::Commerce::StoresController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_commerce_enabled
  before_action :fetch_store, except: [:index]

  rescue_from ::Commerce::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def index
    linked_ids = ::Commerce::CustomerLink.not_suppressed.where(contact: @conversation.contact).pluck(:commerce_store_id)
    render json: {
      payload: active_stores.order(:created_at).map do |store|
        { id: store.id, name: store.name, provider: store.provider, linked: linked_ids.include?(store.id) }
      end
    }
  end

  def show
    render json: panel.show
  end

  def customers
    render json: panel.search(params[:query])
  end

  def link
    render json: panel.link(params[:token])
  end

  def unlink
    panel.unlink
    head :ok
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  # Stores of a provider the installation has switched off stay connected but are not read.
  def active_stores
    Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled)
  end

  def fetch_store
    @store = active_stores.find(params[:id])
  end

  def panel
    ::Commerce::ConversationPanel.new(store: @store, conversation: @conversation, user: Current.user)
  end
end
