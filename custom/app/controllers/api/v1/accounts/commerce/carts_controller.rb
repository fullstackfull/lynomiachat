# The recovery queue (docs/commerce/31-sales-recovery.md §queue): the account's recent abandoned carts across the stores
# that offer them, for administrators. Read-only and bounded: each store's most recent QUEUE_PER_STORE carts, at most
# QUEUE_LIMIT rows. It is a list to act from, not a CRM: no contact details, no recovery links (messages are prepared from
# the conversation), no scores. Priority is deterministic: carts of a linked contact first, then the most recently updated.
#
#   GET /api/v1/accounts/:account_id/commerce/carts[?store_id=&provider=&age=24h|7d|30d&status=abandoned|recovered&linked=true|false]
class Api::V1::Accounts::Commerce::CartsController < Api::V1::Accounts::BaseController
  QUEUE_PER_STORE = 50
  QUEUE_LIMIT = 200
  AGES = { '24h' => 24.hours, '7d' => 7.days, '30d' => 30.days }.freeze
  FIELDS = %w[external_cart_id created_at updated_at currency total items status recovered_at customer_reference].freeze

  before_action :ensure_commerce_enabled
  before_action -> { authorize(::Commerce::Store, :index?) }

  def index
    stores = queue_stores
    views = ::Commerce::Parallel.map(stores, concurrency: 4, timeout: 15) { |store| read(store) }
    rows = stores.zip(views).flat_map { |store, carts| rows(store, carts || []) }
    render json: { payload: prioritized(filtered(rows)).first(QUEUE_LIMIT), stores: stores.map { |store| store_json(store) } }
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def queue_stores
    scope = Current.account.commerce_stores.active.where(provider: ::Commerce::Providers.enabled).order(:created_at)
    scope = scope.where(id: params[:store_id]) if params[:store_id].present?
    scope = scope.where(provider: params[:provider]) if params[:provider].present?
    scope.select { |store| ::Commerce::AbandonedCarts.offered?(store) }
  end

  # The store's recent carts (ids, amounts, status, its customer id only), cached like every store read.
  def read(store)
    ::Commerce::Cache.fetch(store, :cart_queue, 'recent') do
      ::Commerce::Providers.for(store).abandoned_carts(limit: QUEUE_PER_STORE).map { |cart| cart.to_h.stringify_keys.slice(*FIELDS) }
    end.value
  rescue ::Commerce::Error
    []
  end

  def rows(store, carts)
    links = store.customer_links.not_suppressed.where(external_customer_id: carts.filter_map { |cart| cart['customer_reference'] }.uniq)
                 .includes(:contact).index_by(&:external_customer_id)
    states = ::Commerce::RecoveryMessages.states(store, carts.pluck('external_cart_id'))
    carts.map do |cart|
      contact = links[cart['customer_reference']]&.contact
      cart.except('customer_reference', 'items').merge('store' => store_json(store), 'contact' => contact&.slice(:id, :name),
                                                       'items_count' => cart['items'].sum { |item| item['quantity'].to_i },
                                                       'recovery' => states[cart['external_cart_id']])
    end
  end

  def filtered(rows)
    age = AGES[params[:age].to_s]
    rows.select { |row| recent?(row, age) && (params[:status].blank? || row['status'] == params[:status]) && linked?(row) }
  end

  def recent?(row, age) = age.nil? || (row['created_at'].present? && Time.iso8601(row['created_at']) > age.ago)

  def linked?(row) = params[:linked].blank? || row['contact'].present? == (params[:linked] == 'true')

  def prioritized(rows)
    rows.sort_by { |row| [row['contact'] ? 0 : 1, -Time.iso8601(row['updated_at'] || row['created_at'] || Time.at(0).utc.iso8601).to_i] }
  end

  def store_json(store) = { id: store.id, name: store.name, provider: store.provider }
end
