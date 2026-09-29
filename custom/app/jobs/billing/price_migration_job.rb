# frozen_string_literal: true

# Moves every Stripe subscriber of a plan to the plan's current Stripe price.
# proration_behavior "none": the current (already paid) period is not touched,
# the new price is charged from the next invoice.
class Billing::PriceMigrationJob < ApplicationJob
  queue_as :default

  def perform(plan_id)
    plan = BillingPlan.find_by(id: plan_id)
    return if plan.nil? || plan.stripe_price_id.blank?

    subscriptions_to_move(plan).find_each do |subscription|
      move(subscription, plan)
    rescue Stripe::StripeError => e
      # One failing subscriber must not stop the others
      Rails.logger.error("[Billing] Price migration failed for account #{subscription.account_id}: #{e.message}")
    end
  end

  private

  def subscriptions_to_move(plan)
    plan.subscriptions
        .where(source: 'stripe', status: %w[active past_due])
        .where.not(stripe_subscription_id: nil)
        .where.not(stripe_price_id: plan.stripe_price_id)
  end

  def move(subscription, plan)
    opts = { api_key: Billing::Settings.stripe_secret_key }
    stripe_sub = Stripe::Subscription.retrieve(subscription.stripe_subscription_id, opts)
    item = stripe_sub.items.data.first
    return if item.price.id == plan.stripe_price_id

    updated = Stripe::Subscription.update(
      stripe_sub.id,
      {
        items: [{ id: item.id, price: plan.stripe_price_id, quantity: item.quantity }],
        proration_behavior: 'none'
      },
      opts
    )
    Billing::SubscriptionSync.new(updated).perform
    Rails.logger.info("[Billing] Account #{subscription.account_id} moved to price #{plan.stripe_price_id}")
  end
end
