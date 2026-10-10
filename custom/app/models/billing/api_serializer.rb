# frozen_string_literal: true

# JSON shapes used by the billing Platform API (one place, same shape everywhere).
module Billing::ApiSerializer
  module_function

  def plan(plan)
    {
      id: plan.id,
      name: plan.name,
      description: plan.description,
      price: plan.price,
      price_cents: plan.price_cents,
      currency: plan.currency,
      interval: plan.interval,
      pricing_type: plan.pricing_type,
      limits: plan.limits,
      features: plan.features,
      active: plan.active,
      position: plan.position,
      subscribers_count: plan.subscriptions.where(status: %w[trialing active past_due]).count,
      stripe_product_id: plan.stripe_product_id,
      stripe_price_id: plan.stripe_price_id,
      created_at: plan.created_at,
      updated_at: plan.updated_at
    }
  end

  def subscription(subscription, with_usage: false)
    return nil if subscription.nil?

    account = subscription.account
    data = {
      id: subscription.id,
      account: account && { id: account.id, name: account.name, status: account.status },
      plan: subscription.plan && { id: subscription.plan.id, name: subscription.plan.name }
    }.merge(subscription_state(subscription), subscription_stripe_fields(subscription))
    data[:usage] = usage(account) if with_usage && account
    data
  end

  def subscription_state(subscription)
    {
      status: subscription.status,
      usable: subscription.usable?,
      source: subscription.source,
      quantity: subscription.quantity,
      trial_ends_at: subscription.trial_ends_at,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      grace_period_ends_at: subscription.grace_period_ends_at
    }
  end

  def subscription_stripe_fields(subscription)
    {
      stripe_customer_id: subscription.stripe_customer_id,
      stripe_subscription_id: subscription.stripe_subscription_id,
      stripe_price_id: subscription.stripe_price_id,
      created_at: subscription.created_at,
      updated_at: subscription.updated_at
    }
  end

  # The limit reported is the one that is ENFORCED, through Billing::ResourceLimit -- so an operator's
  # override is the number the customer and the console both see, not the plan's. A number on a screen that
  # differs from what the server will do is the dishonesty P11.28 is about. `limit: nil` means unlimited and
  # is rendered as such; it is never -1.
  def usage(account)
    BillingPlan::LIMIT_KEYS.to_h do |key|
      resource = key.to_sym
      [resource, { used: ::Billing::ResourceLimit.current_count(account, resource),
                   limit: ::Billing::Entitlements.limit(account, resource) }]
    end
  end

  # Secrets are never returned, only whether they are set + a masked hint
  def settings
    values = ::Billing::Settings.all
    secrets = ::Billing::Settings::KEYS.select { |_key, definition| definition[:type] == :secret }.keys

    values.to_h do |key, value|
      if secrets.include?(key)
        [key, { set: value.present?, masked: ::Billing::Settings.masked(key) }]
      else
        [key, value]
      end
    end.merge(stripe_configured: ::Billing::Settings.stripe_configured?)
  end
end
