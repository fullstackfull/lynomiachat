# GET /platform/api/v1/accounts/:account_id/integration_health
#
# One partner installation's operational state, read by the partner that owns it. See
# Operations::IntegrationHealth for what is in the payload and why the allow-list is written
# out rather than serialized from a model.
#
# AUTHORIZATION IS DECLARED HERE, NOT INHERITED. PlatformController applies `set_resource` and
# `validate_platform_app_permissible` with `only: [:update, :show, :destroy]`, so an action
# named anything else -- :health, :status, :summary -- silently gets neither, and an endpoint
# written that way would answer any valid token for any account id in the URL. The action is
# `show` AND both filters are restated, so neither the name nor a future edit to the base
# class can quietly remove the check.
#
# A SINGULAR RESOURCE. There is one answer per installation and it is addressed by the account
# it is about, so there is no id for a caller to hold and nothing to keep in step.
class Platform::Api::V1::IntegrationHealthController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def show
    render json: Operations::IntegrationHealth.new(@resource, @platform_app).call
  end

  private

  def set_resource
    @resource = Account.find_by(id: params[:account_id])
    return if @resource

    # The same answer as a non-permissible account, deliberately: whether an account id exists
    # on this installation is not something an unauthorized caller gets to learn by asking.
    render json: { error: 'Non permissible resource', error_code: 'non_permissible_resource' },
           status: :unauthorized
  end
end
