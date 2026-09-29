# frozen_string_literal: true

# Copies the state of a Stripe subscription into our BillingSubscription row.
# Stripe is the source of truth; this is safe to run many times (idempotent).
class Billing::SubscriptionSync
  STATUS_MAP = {
    'active' => 'active',
    'trialing' => 'active', # a real subscription with a card, first charge later
    'past_due' => 'past_due',
    'unpaid' => 'past_due',
    'canceled' => 'canceled',
    'incomplete_expired' => 'canceled',
    'incomplete' => 'inactive',
    'paused' => 'inactive'
  }.freeze
  TERMINAL = %w[canceled incomplete_expired].freeze

  def initialize(stripe_subscription, account_id: nil)
    @stripe_sub = stripe_subscription
    @account_id = account_id
  end

  def perform
    subscription = find_subscription
    if subscription.nil?
      Rails.logger.warn("[Billing] No account found for Stripe subscription #{@stripe_sub.id}")
      return
    end
    return if stale_event?(subscription)

    apply(subscription)
    subscription.save!
    subscription
  end

  private

  def find_subscription
    BillingSubscription.find_by(stripe_subscription_id: @stripe_sub.id) ||
      (account_id && BillingSubscription.find_or_initialize_by(account_id: account_id))
  end

  def account_id
    id = @account_id.presence || @stripe_sub.metadata['account_id']
    return nil if id.blank?

    Account.exists?(id: id) ? id.to_i : nil
  end

  # An ended Stripe subscription must not overwrite the account's current state:
  # - a newer Stripe subscription, or
  # - a plan granted manually by the super admin
  def stale_event?(subscription)
    return false unless TERMINAL.include?(@stripe_sub.status)
    return true if subscription.manual?

    subscription.stripe_subscription_id.present? && subscription.stripe_subscription_id != @stripe_sub.id
  end

  def apply(subscription)
    status = STATUS_MAP.fetch(@stripe_sub.status, 'inactive')

    subscription.assign_attributes(
      source: 'stripe',
      status: status,
      stripe_subscription_id: @stripe_sub.id,
      stripe_customer_id: id_of(@stripe_sub.customer),
      **price_attributes(subscription),
      current_period_end: timestamp(item_value(:current_period_end) || @stripe_sub[:current_period_end]),
      cancel_at_period_end: @stripe_sub[:cancel_at_period_end] || false
    )
    subscription.grace_period_ends_at = grace_period_for(subscription, status)
  end

  def price_attributes(subscription)
    price = item&.price
    {
      stripe_price_id: price&.id,
      plan: plan_for(price) || subscription.plan,
      quantity: item&.quantity || 1
    }
  end

  def item
    @stripe_sub.items&.data&.first
  end

  def item_value(key)
    item && item[key]
  end

  def plan_for(price)
    return nil if price.nil?

    BillingPlan.find_by(stripe_price_id: price.id) ||
      BillingPlan.find_by(stripe_product_id: id_of(price.product))
  end

  def grace_period_for(subscription, status)
    return nil unless status == 'past_due'

    subscription.grace_period_ends_at || Billing::Settings.grace_period_days.days.from_now
  end

  def id_of(value)
    value.is_a?(String) ? value : value&.id
  end

  def timestamp(value)
    value.present? ? Time.zone.at(value) : nil
  end
end
