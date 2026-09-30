# Lynomia Commerce store connections (administrators, `lynomia_commerce` accounts only).
#
#   GET    /api/v1/accounts/:account_id/commerce/stores       list
#   POST   /api/v1/accounts/:account_id/commerce/stores       connect: provider, base_url, consumer_key, consumer_secret, name
#   PATCH  /api/v1/accounts/:account_id/commerce/stores/:id   name, status (active|disabled), consumer_key + consumer_secret
#   DELETE /api/v1/accounts/:account_id/commerce/stores/:id   disconnect (credentials and customer links deleted)
#
# Credentials are write-only: they are accepted here and never rendered back.
class Api::V1::Accounts::Commerce::StoresController < Api::V1::Accounts::BaseController
  WOOCOMMERCE_KEY_FORMATS = { consumer_key: /\Ack_[0-9a-f]{40}\z/, consumer_secret: /\Acs_[0-9a-f]{40}\z/ }.freeze

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
    raise ActionController::ParameterMissing, :provider unless params[:provider] == 'woocommerce'

    @store = connection.connect(provider: 'woocommerce', base_url: params[:base_url].to_s, credentials: credentials_param,
                                name: params[:name].to_s.strip)
    render :show, status: :created
  end

  def update
    @store.update!(name: params[:name].to_s.strip) if params.key?(:name)
    connection.rotate_credentials(@store, credentials_param) if params.key?(:consumer_key) || params.key?(:consumer_secret)
    change_status if params.key?(:status)
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

  def credentials_param
    WOOCOMMERCE_KEY_FORMATS.to_h do |key, format|
      value = params[key].to_s.strip
      raise ActionController::ParameterMissing, key unless value.match?(format)

      [key.to_s, value]
    end
  end

  def connection
    ::Commerce::StoreConnection.new(account: Current.account, user: Current.user)
  end
end
