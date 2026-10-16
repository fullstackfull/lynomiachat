# POST /platform/api/v1/accounts/:account_id/installation_lifecycle
#
# A partner telling Lynomia that one of its installations has been suspended, brought back or
# decommissioned on its own side. See Commerce::InstallationLifecycle for what each transition
# means and why it is a facade rather than a second lifecycle.
#
# AUTHORIZATION IS DECLARED, NOT INHERITED -- the same trap as every other endpoint under this
# base. PlatformController applies `set_resource` and `validate_platform_app_permissible` with
# `only: [:update, :show, :destroy]`, so an action named `create` -- which is what a POST to a
# singular resource routes to by default -- would inherit NEITHER and accept any valid token
# for any account id in the URL. The action is therefore `update`, which is in that list, AND
# both filters are restated so neither a rename nor an edit to the base can remove the check.
#
# VALIDATED AT THE BOUNDARY. A missing or unknown transition is a 422 from here, not an
# exception from a service or a row written in a state nobody declared.
class Platform::Api::V1::InstallationLifecycleController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def update
    render json: lifecycle.apply(
      provider: params.require(:provider), external_store_id: params.require(:external_store_id),
      transition: params.require(:transition), reason: params[:reason], actor: params[:actor]
    )
  rescue ActionController::ParameterMissing => e
    render json: { error: "#{e.param} is required", error_code: 'invalid_request' }, status: :unprocessable_entity
  rescue Commerce::InstallationLifecycle::Refused => e
    render json: { error: e.message, error_code: e.code }, status: status_for(e)
  end

  private

  def lifecycle
    Commerce::InstallationLifecycle.new(account: @resource, platform_app: @platform_app)
  end

  # An installation this account does not have is the caller's mistake and will be the same
  # mistake next time, so it is a 404 the partner's client classes permanent. A resume that
  # could not reach the store is a condition that may well have changed by the next attempt,
  # so it is a 409 rather than anything the partner would retire.
  def status_for(error)
    case error.code
    when 'installation_not_found' then :not_found
    when 'resume_failed' then :conflict
    else :unprocessable_entity
    end
  end

  def set_resource
    @resource = Account.find_by(id: params[:account_id])
    return if @resource

    render json: { error: 'Non permissible resource', error_code: 'non_permissible_resource' },
           status: :unauthorized
  end
end
