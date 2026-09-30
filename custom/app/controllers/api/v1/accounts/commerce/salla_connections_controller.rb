# Connecting a Salla store (administrators, `lynomia_commerce` accounts, installations that offer Salla).
#
#   POST /api/v1/accounts/:account_id/commerce/salla_connection   a one-time connection code, shown once (replaces the previous one)
#   GET  /api/v1/accounts/:account_id/commerce/salla_connection   progress: none | waiting | expired | claimed | connected | conflict
#
# The merchant installs the Lynomia app from Salla and enters the code in its settings; Salla's signed events then
# connect the store (docs/commerce/10-salla-install-correlation.md). No token ever passes through the browser.
class Api::V1::Accounts::Commerce::SallaConnectionsController < Api::V1::Accounts::BaseController
  before_action :ensure_commerce_enabled
  before_action -> { authorize(::Commerce::Store, :create?) }
  before_action :ensure_salla_enabled

  rescue_from ::Commerce::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def show
    render json: ::Commerce::Salla::ConnectionCode.status(Current.account)
  end

  def create
    raise ::Commerce::Error, 'ENCRYPTION_NOT_CONFIGURED' unless Chatwoot.encryption_configured?

    render json: ::Commerce::Salla::ConnectionCode.create(account: Current.account, user: Current.user), status: :created
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def ensure_salla_enabled
    raise ::Commerce::Error, 'PROVIDER_DISABLED' unless ::Commerce::Providers.enabled?('salla')
  end
end
