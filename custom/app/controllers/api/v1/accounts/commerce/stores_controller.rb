# Lynomia Commerce store connections (administrators, `lynomia_commerce` accounts only).
#
#   GET    /api/v1/accounts/:account_id/commerce/stores       list, with the providers this installation offers
#   POST   /api/v1/accounts/:account_id/commerce/stores       connect a key-pasting provider: provider, base_url, its credentials, name
#   PATCH  /api/v1/accounts/:account_id/commerce/stores/:id   name, status (active|disabled), the provider's credentials again to
#                                                             rotate them, order_actions (true|false: the store's opt-in to order actions)
#   DELETE /api/v1/accounts/:account_id/commerce/stores/:id   disconnect (credentials and customer links deleted)
#
# Credentials are write-only: they are accepted here and never rendered back. Only the providers in CREDENTIAL_FORMATS
# connect here, because only they are credentials an administrator can hold: Salla, Zid and Shopify stores are connected
# through their app installation controllers instead, and never take keys here.
class Api::V1::Accounts::Commerce::StoresController < Api::V1::Accounts::BaseController
  # Each provider's credential keys and the exact shape each one has, so a mistyped or pasted-wrong value is a 422 here
  # rather than a failed health check or a store saved with a credential that can never work.
  CREDENTIAL_FORMATS = {
    'woocommerce' => { consumer_key: /\Ack_[0-9a-f]{40}\z/, consumer_secret: /\Acs_[0-9a-f]{40}\z/ },
    # Store Syria mints lsc_{store}_{revocation version}_{hmac-sha256}. The store and the version travel in the clear
    # because they are the lookup, not the secret; the hmac covers both, so the token cannot be edited to name another
    # store or to resurrect a revoked version.
    'storesyria' => { commerce_token: /\Alsc_\d{1,19}_\d{1,19}_[0-9a-f]{64}\z/ }
  }.freeze
  CREDENTIAL_KEYS = CREDENTIAL_FORMATS.values.flat_map(&:keys).freeze

  before_action :ensure_commerce_enabled
  before_action -> { authorize(::Commerce::Store) }
  before_action :fetch_store, only: [:update, :destroy]

  rescue_from ::Commerce::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def index
    @stores = Current.account.commerce_stores.order(:created_at)
  end

  def create
    params.require(:base_url)
    provider = params[:provider].to_s
    raise ActionController::ParameterMissing, :provider unless CREDENTIAL_FORMATS.key?(provider)

    @store = connection.connect(provider: provider, base_url: params[:base_url].to_s, credentials: credentials_param(provider),
                                name: params[:name].to_s.strip)
    render :show, status: :created
  end

  def update
    @store.update!(name: params[:name].to_s.strip) if params.key?(:name)
    connection.rotate_credentials(@store, credentials_param(@store.provider)) if CREDENTIAL_KEYS.any? { |key| params.key?(key) }
    change_status if params.key?(:status)
    change_order_actions if params.key?(:order_actions)
    render :show
  end

  def destroy
    connection.disconnect(@store)
    head :ok
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def fetch_store
    @store = Current.account.commerce_stores.find(params[:id])
  end

  def change_status
    case params[:status]
    when 'active' then connection.enable(@store)
    when 'disabled' then connection.disable(@store)
    else raise ActionController::ParameterMissing, :status
    end
  end

  def change_order_actions
    raise ActionController::ParameterMissing, :order_actions unless [true, false].include?(params[:order_actions])

    connection.change_order_actions(@store, params[:order_actions])
  end

  # A credential sent to a store whose provider does not take one here is a 422 naming the provider, not a silent no-op.
  def credentials_param(provider)
    formats = CREDENTIAL_FORMATS[provider]
    raise ActionController::ParameterMissing, :provider if formats.nil?

    formats.to_h do |key, format|
      value = params[key].to_s.strip
      raise ActionController::ParameterMissing, key unless value.match?(format)

      [key.to_s, value]
    end
  end

  def connection
    ::Commerce::StoreConnection.new(account: Current.account, user: Current.user)
  end
end
