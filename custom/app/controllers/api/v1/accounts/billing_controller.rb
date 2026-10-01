# frozen_string_literal: true

# Account-level billing API used by the dashboard subscription page and the mobile app.
#
#   GET  /api/v1/accounts/:account_id/billing                      -> current state + plans (dashboard page)
#   GET  /api/v1/accounts/:account_id/billing/plans                -> plans the account can subscribe to
#   GET  /api/v1/accounts/:account_id/billing/entitlements         -> is the account active + features + limits
#   POST /api/v1/accounts/:account_id/billing/checkout             -> { url } Stripe Checkout (admins)
#   POST /api/v1/accounts/:account_id/billing/portal               -> { url } Stripe Customer Portal (admins)
#        both accept "mobile": true -> after Stripe, the customer is sent back to the mobile app
#   POST /api/v1/accounts/:account_id/billing/change_plan_preview  -> amount to pay / credit now (admins)
#   POST /api/v1/accounts/:account_id/billing/change_plan          -> change plan immediately (admins)
#
# These endpoints stay available when the account is locked (see Billing::AccessGuard).
class Api::V1::Accounts::BillingController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator, only: [:checkout, :portal, :change_plan_preview, :change_plan]

  def show
    render json: {
      stripe_configured: Billing::Settings.stripe_configured?,
      is_admin: administrator?,
      subscription: subscription_json(Current.account.billing_subscription),
      plans: subscribable_plans.map { |plan| plan_json(plan) },
      usage: {
        agents: Current.account.users.count,
        inboxes: Current.account.inboxes.count,
        stores: Current.account.commerce_stores.connected.count
      }
    }
  end

  def plans
    current_plan_id = Current.account.billing_subscription&.plan_id
    render json: {
      mobile_checkout_enabled: Billing::Settings.mobile_checkout_enabled?,
      plans: subscribable_plans.map do |plan|
        plan_json(plan).merge(
          features: plan.features.map { |name| { name: name, display_name: feature_names[name] || name } },
          is_current: plan.id == current_plan_id
        )
      end
    }
  end

  def entitlements
    account = Current.account
    subscription = Billing::TrialStarter.subscription_for(account)
    plan = subscription&.plan

    render json: {
      active: account_open?(subscription),
      status: subscription&.status || 'inactive',
      source: subscription&.source,
      plan: plan && { id: plan.id, name: plan.name },
      ends_at: ends_at(subscription),
      cancel_at_period_end: subscription&.cancel_at_period_end || false,
      is_admin: administrator?,
      mobile_checkout_enabled: Billing::Settings.mobile_checkout_enabled?,
      features: BillingPlan.assignable_features.to_h { |f| [f['name'], account.feature_enabled?(f['name'])] },
      limits: Billing::ApiSerializer.usage(account, plan)
    }
  end

  def checkout
    return render json: { error: 'mobile_checkout_disabled' }, status: :forbidden if mobile_request? && !Billing::Settings.mobile_checkout_enabled?

    url = Billing::Checkout.new(account: Current.account, plan: requested_plan, user: current_user, mobile: mobile_request?).perform
    render json: { url: url }
  rescue Billing::Checkout::Error, Stripe::StripeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def portal
    customer_id = Current.account.billing_subscription&.stripe_customer_id
    return render json: { error: 'No billing account yet' }, status: :unprocessable_entity if customer_id.blank?

    session = Stripe::BillingPortal::Session.create(
      { customer: customer_id, return_url: mobile_request? ? mobile_return_page('portal') : billing_page_url },
      { api_key: Billing::Settings.stripe_secret_key }
    )
    render json: { url: session.url }
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def change_plan_preview
    render json: Billing::PlanChange.new(account: Current.account, plan: requested_plan).preview
  rescue Billing::PlanChange::Error, Stripe::StripeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def change_plan
    Billing::PlanChange.new(account: Current.account, plan: requested_plan)
                       .perform(proration_date: params[:proration_date])
    render json: { subscription: subscription_json(Current.account.billing_subscription.reload) }
  rescue Billing::PlanChange::Error, Stripe::StripeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def subscribable_plans
    BillingPlan.active.ordered.where.not(stripe_price_id: nil)
  end

  def requested_plan
    BillingPlan.active.find(params.require(:plan_id))
  end

  # Same rule as Billing::AccessGuard
  def account_open?(subscription)
    subscription.nil? || subscription.accessible?
  end

  def ends_at(subscription)
    case subscription&.status
    when 'trialing' then subscription.trial_ends_at
    when 'active' then subscription.current_period_end
    when 'past_due' then subscription.grace_period_ends_at
    end
  end

  def feature_names
    @feature_names ||= BillingPlan.assignable_features.to_h { |f| [f['name'], f['display_name']] }
  end

  def administrator?
    Current.account.account_users.find_by(user_id: current_user.id)&.administrator? || false
  end

  def ensure_administrator
    render json: { error: 'Only administrators can manage billing' }, status: :forbidden unless administrator?
  end

  def mobile_request?
    ActiveModel::Type::Boolean.new.cast(params[:mobile]) || false
  end

  def mobile_return_page(result)
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/mobile/billing/return?checkout=#{result}&account_id=#{Current.account.id}"
  end

  def billing_page_url
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/app/accounts/#{Current.account.id}/settings/subscription"
  end

  def subscription_json(subscription)
    return nil if subscription.nil?

    {
      status: subscription.status,
      usable: subscription.usable?,
      source: subscription.source,
      plan_id: subscription.plan_id,
      plan_name: subscription.plan&.name,
      # The subscribed plan's own limits: a plan granted by the super admin may have no Stripe price, so it is not in `plans`.
      plan_limits: subscription.plan&.limits || {},
      plan_commerce: subscription.plan&.feature_included?('lynomia_commerce') || false,
      scheduled_plan_id: subscription.scheduled_plan_id,
      quantity: subscription.quantity,
      trial_ends_at: subscription.trial_ends_at,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      grace_period_ends_at: subscription.grace_period_ends_at,
      has_billing_account: subscription.stripe_customer_id.present?
    }
  end

  def plan_json(plan)
    {
      id: plan.id,
      name: plan.name,
      description: plan.description,
      price: plan.price,
      currency: plan.currency,
      interval: plan.interval,
      pricing_type: plan.pricing_type,
      limits: plan.limits,
      features: plan.features.map { |name| feature_names[name] || name },
      commerce: plan.feature_included?('lynomia_commerce')
    }
  end
end
