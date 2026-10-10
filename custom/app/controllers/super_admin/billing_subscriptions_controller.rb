# frozen_string_literal: true

# Super admin management of account subscriptions.
# List + show come from Administrate (BillingSubscriptionDashboard);
# the actions below are the buttons on the show page.
class SuperAdmin::BillingSubscriptionsController < SuperAdmin::ApplicationController
  helper_method :stripe_paid?

  # POST /super_admin/billing_subscriptions/:id/extend_trial  (days)
  def extend_trial
    subscription = requested_resource
    days = params[:days].to_i
    return back_with(error: 'Days must be more than 0.') unless days.positive?
    return back_with(error: paid_error) if stripe_paid?(subscription)

    plan = subscription.plan || Billing::Settings.trial_plan
    return back_with(error: 'Choose a trial plan in Billing Settings first.') if plan.nil?

    start = [subscription.trial_ends_at, Time.current].compact.max
    subscription.update!(
      status: 'trialing',
      source: 'stripe',
      plan: plan,
      trial_ends_at: start + days.days,
      grace_period_ends_at: nil,
      cancel_at_period_end: false
    )
    back_with(notice: "Trial extended until #{subscription.trial_ends_at.strftime('%d %b %Y')}.")
  end

  # POST /super_admin/billing_subscriptions/:id/grant_plan  (plan_id, ends_at optional)
  def grant_plan
    subscription = requested_resource
    plan = BillingPlan.find_by(id: params[:plan_id])
    return back_with(error: 'Choose a plan.') if plan.nil?
    return back_with(error: paid_error) if stripe_paid?(subscription)

    ends_at = end_date(:ends_at)
    return back_with(error: 'The end date is not valid.') if ends_at == :invalid

    subscription.update!(manual_grant_attributes(plan, ends_at))
    until_text = ends_at ? "until #{ends_at.strftime('%d %b %Y')}" : 'with no end date'
    back_with(notice: "Plan #{plan.name} granted #{until_text}.")
  end

  # POST /super_admin/billing_subscriptions/:id/grant_override  (kind, name, value, reason, expires_at optional)
  #
  # An explicit commercial exception for this one account. It is deliberately NOT a plan edit: a plan edit
  # moves every subscriber, and the thing an operator actually needs is "this customer, this capability,
  # because X". Billing::OverrideGrant writes the audit row.
  def grant_override
    return back_with(error: 'Unknown override kind.') unless BillingEntitlementOverride.kinds.key?(override_kind)

    expires_at = end_date(:expires_at)
    return back_with(error: 'The expiry date is not valid.') if expires_at == :invalid

    value = override_value
    return back_with(error: 'The limit must be a whole number.') if override_kind == 'limit' && value.nil?

    override = override_grant.grant!(kind: override_kind, name: params[:name], reason: params[:reason].to_s.strip,
                                     value: value, expires_at: expires_at)
    back_with(notice: "Override saved: #{override.kind} #{override.name}.")
  rescue Billing::OverrideGrant::Error => e
    back_with(error: e.message)
  end

  # POST /super_admin/billing_subscriptions/:id/revoke_override  (override_id)
  def revoke_override
    account = requested_resource.account
    override = account&.billing_entitlement_overrides&.find_by(id: params[:override_id])
    return back_with(error: 'That override no longer exists.') if override.nil?

    override_grant.revoke!(override)
    back_with(notice: "Override removed: #{override.kind} #{override.name}.")
  end

  # POST /super_admin/billing_subscriptions/:id/cancel_subscription
  def cancel_subscription
    subscription = requested_resource
    Billing::SubscriptionCanceller.new(subscription).perform
    subscription.update!(status: 'canceled', cancel_at_period_end: false, grace_period_ends_at: nil)
    back_with(notice: 'Subscription canceled. The account is now locked.')
  rescue Stripe::StripeError => e
    back_with(error: "Stripe error, nothing was changed: #{e.message}")
  end

  private

  def override_grant
    Billing::OverrideGrant.new(requested_resource.account, actor: current_super_admin)
  end

  def override_kind
    params[:kind].to_s
  end

  # A feature or channel override answers yes/no, a limit override answers a number. nil for an unreadable
  # number, which the caller turns into a 'whole number' message rather than the model's 'is required'.
  def override_value
    return ActiveModel::Type::Boolean.new.cast(params[:value]) unless override_kind == 'limit'

    Integer(params[:value], exception: false)
  end

  # nil = no end date, :invalid = unreadable or in the past
  def end_date(param)
    return if params[param].blank?

    ends_at = Time.zone.parse(params[param].to_s)&.end_of_day
    ends_at.nil? || ends_at.past? ? :invalid : ends_at
  rescue ArgumentError # e.g. "2026-13-45"
    :invalid
  end

  def manual_grant_attributes(plan, ends_at)
    {
      source: 'manual',
      status: 'active',
      plan: plan,
      current_period_end: ends_at,
      trial_ends_at: nil,
      grace_period_ends_at: nil,
      cancel_at_period_end: false,
      stripe_subscription_id: nil,
      stripe_price_id: nil
    }
  end

  def stripe_paid?(subscription)
    subscription.source == 'stripe' &&
      subscription.stripe_subscription_id.present? &&
      %w[active past_due].include?(subscription.status)
  end

  def paid_error
    'This account has a paid Stripe subscription. Cancel it first.'
  end

  def back_with(flash_message)
    redirect_to super_admin_billing_subscription_path(requested_resource), flash: flash_message
  end
end
