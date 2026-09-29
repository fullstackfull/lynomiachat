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

    ends_at = nil
    if params[:ends_at].present?
      ends_at = Time.zone.parse(params[:ends_at].to_s)&.end_of_day
      return back_with(error: 'The end date is not valid.') if ends_at.nil? || ends_at.past?
    end

    subscription.update!(
      source: 'manual',
      status: 'active',
      plan: plan,
      current_period_end: ends_at,
      trial_ends_at: nil,
      grace_period_ends_at: nil,
      cancel_at_period_end: false,
      stripe_subscription_id: nil,
      stripe_price_id: nil
    )
    until_text = ends_at ? "until #{ends_at.strftime('%d %b %Y')}" : 'with no end date'
    back_with(notice: "Plan #{plan.name} granted #{until_text}.")
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