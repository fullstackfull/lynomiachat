# Ceilings an integration includes with its own product.
#
#   GET    /platform/api/v1/accounts/:account_id/entitlement_grants  what is granted, and what is effective
#   PUT    /platform/api/v1/accounts/:account_id/entitlement_grants  set one
#   DELETE /platform/api/v1/accounts/:account_id/entitlement_grants  withdraw one
#
# WHAT THIS IS FOR. An external platform that bundles Lynomia into its own packages has to be able
# to say "this merchant's plan includes five agents" without giving them a Lynomia subscription --
# because a subscription is a second place they could be charged for seats they have already paid
# for once.
#
# IT DOES NOT OVERRIDE AN OPERATOR. Billing::Entitlements puts an operator's explicit override
# above this layer and composes this one with the plan by MAX, so an integration can raise a
# merchant's ceiling but can neither lower one they pay Lynomia for nor overrule a deliberate
# decision somebody made about their account. A sync that could do either would be a machine
# quietly undoing a human.
#
# WITHDRAWING A GRANT DOES NOT REMOVE ANYBODY. Seats already in use stay; the ceiling simply stops
# applying, and the next attempt to add somebody is measured against whatever is left. Deleting
# people because a plan changed is not something an integration should be able to cause.
class Platform::Api::V1::EntitlementGrantsController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def index
    render json: {
      account_id: @resource.id,
      grants: grants.map { |grant| present(grant) },
      effective: BillingPlan::LIMIT_KEYS.index_with { |resource| effective(resource) }
    }
  end

  def update
    resource_key = params[:resource].to_s
    return render_invalid("resource must be one of #{BillingPlan::LIMIT_KEYS.join(', ')}") unless valid_resource?(resource_key)

    value = params[:limit_value]
    return render_invalid('limit_value must be a non-negative integer') unless non_negative_integer?(value)

    grant = PlatformAppEntitlementGrant.find_or_initialize_by(
      platform_app_id: @platform_app.id, account_id: @resource.id, resource: resource_key
    )
    grant.update!(limit_value: value.to_i, external_ref: params[:external_ref].presence)

    render json: present(grant).merge(effective: effective(resource_key))
  end

  def destroy
    resource_key = params[:resource].to_s
    return render_invalid("resource must be one of #{BillingPlan::LIMIT_KEYS.join(', ')}") unless valid_resource?(resource_key)

    removed = PlatformAppEntitlementGrant.where(
      platform_app_id: @platform_app.id, account_id: @resource.id, resource: resource_key
    ).destroy_all

    render json: { withdrawn: removed.any?, effective: effective(resource_key) }
  end

  private

  def grants
    PlatformAppEntitlementGrant.where(platform_app_id: @platform_app.id, account_id: @resource.id)
  end

  # The number that is actually enforced, and which layer produced it. An integration showing a
  # merchant "5 of 5 seats used" must show the EFFECTIVE ceiling, not its own grant -- those
  # differ whenever the account also has a plan or an operator override.
  def effective(resource_key)
    {
      limit: Billing::Entitlements.limit(@resource, resource_key),
      source: Billing::Entitlements.limit_source(@resource, resource_key),
      used: Billing::ResourceLimit.current_count(@resource, resource_key)
    }
  end

  def valid_resource?(resource_key)
    BillingPlan::LIMIT_KEYS.include?(resource_key)
  end

  def non_negative_integer?(value)
    value.to_s.match?(/\A\d+\z/)
  end

  def present(grant)
    {
      resource: grant.resource, limit_value: grant.limit_value,
      external_ref: grant.external_ref, granted_at: grant.created_at
    }
  end

  def render_invalid(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def set_resource
    @resource = Account.find(params[:account_id])
  end
end
