# The conversation contact's abandoned carts (docs/commerce/30-abandoned-carts.md), for the Customer 360 section: every
# store that offers them, read concurrently, each answering on its own. The same people who can see the conversation's
# Commerce section see them; nothing here changes a store.
#
#   GET .../conversations/:conversation_id/commerce/carts[?store_id=:id]
class Api::V1::Accounts::Conversations::Commerce::CartsController < Api::V1::Accounts::Conversations::BaseController
  MAX_CONCURRENCY = 4
  STORE_TIMEOUT = 15

  before_action :ensure_commerce_enabled

  def index
    stores = carts_stores
    stores = [stores.find(params[:store_id])] if params[:store_id].present?
    views = ::Commerce::Parallel.map(stores.to_a, concurrency: MAX_CONCURRENCY, timeout: STORE_TIMEOUT) do |store|
      ::Commerce::AbandonedCarts.new(store: store, conversation: @conversation).list
    end
    render json: { stores: stores.zip(views).map { |store, view| with_recovery(store, view || timed_out(store)) } }
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def carts_stores
    ids = Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled).order(:created_at)
                 .select { |store| ::Commerce::AbandonedCarts.offered?(store) }.map(&:id)
    Current.account.commerce_stores.where(id: ids).order(:created_at)
  end

  # Each cart's recovery messages: when one was prepared, sent, and until when the cooldown runs.
  def with_recovery(store, view)
    states = ::Commerce::RecoveryMessages.states(store, view[:carts].pluck('external_cart_id'))
    view.merge(carts: view[:carts].map { |cart| cart.merge('recovery' => states[cart['external_cart_id']]) })
  end

  def timed_out(store)
    { store: { id: store.id, name: store.name, provider: store.provider }, state: 'unavailable', error: 'TIMEOUT', carts: [] }
  end
end
