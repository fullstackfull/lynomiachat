# frozen_string_literal: true

# Changes the plan of an active Stripe subscription immediately.
#
# prorate: true (default, used by the subscription page)
#   Stripe prorates the remaining days:
#     - upgrade   -> the difference is invoiced and charged right away
#     - downgrade -> the difference becomes credit for the next invoices
#   payment_behavior "pending_if_incomplete": if the charge fails, Stripe does
#   NOT apply the change, so nobody gets a more expensive plan without paying.
#
# prorate: false (admin option in the Platform API)
#   The plan changes now, nothing is charged now, the new price applies from
#   the next invoice.
module Billing
  class PlanChange
    class Error < StandardError; end

    def initialize(account:, plan:, prorate: true)
      @account = account
      @plan = plan
      @prorate = prorate
      @subscription = account.billing_subscription
    end

    # What the customer pays (positive) or gets as credit (negative) right now
    def preview
      validate!
      return preview_result(0) unless @prorate

      invoice = Stripe::Invoice.create_preview(
        {
          customer: @subscription.stripe_customer_id,
          subscription: @subscription.stripe_subscription_id,
          subscription_details: {
            items: new_items,
            proration_behavior: 'always_invoice',
            proration_date: proration_date
          }
        },
        opts
      )
      preview_result(invoice.total, currency: invoice.currency)
    end

    def perform(proration_date: nil)
      validate!
      @proration_date = proration_date.to_i if proration_date.present?

      params = { items: new_items }
      if @prorate
        params.merge!(
          proration_behavior: 'always_invoice',
          proration_date: self.proration_date,
          payment_behavior: 'pending_if_incomplete'
        )
      else
        params[:proration_behavior] = 'none'
      end

      updated = Stripe::Subscription.update(@subscription.stripe_subscription_id, params, opts)
      raise Error, 'The payment for the plan change failed. Please update your card and try again.' if updated.pending_update.present?

      # Apply right away (the webhook will confirm the same state a moment later)
      Billing::SubscriptionSync.new(updated).perform
    end

    private

    def preview_result(total_cents, currency: @plan.currency)
      {
        plan_id: @plan.id,
        plan_name: @plan.name,
        amount: total_cents / 100.0,
        currency: currency,
        prorate: @prorate,
        proration_date: proration_date
      }
    end

    def validate!
      raise Error, 'Stripe is not configured' unless Billing::Settings.stripe_configured?
      raise Error, 'Plan is not available' unless @plan.active? && @plan.stripe_price_id.present?
      raise Error, 'There is no active subscription to change' unless changeable_subscription?
      raise Error, 'You are already on this plan' if @subscription.plan_id == @plan.id
    end

    def changeable_subscription?
      @subscription.present? &&
        @subscription.source == 'stripe' &&
        @subscription.status == 'active' &&
        @subscription.stripe_subscription_id.present?
    end

    def new_items
      [{ id: stripe_item_id, price: @plan.stripe_price_id, quantity: quantity }]
    end

    def stripe_item_id
      @stripe_item_id ||= Stripe::Subscription.retrieve(@subscription.stripe_subscription_id, opts).items.data.first.id
    end

    def quantity
      @plan.pricing_type == 'per_agent' ? [@account.users.count, 1].max : 1
    end

    # Same timestamp for preview and change, so the charged amount matches what was shown
    def proration_date
      @proration_date ||= Time.current.to_i
    end

    def opts
      { api_key: Billing::Settings.stripe_secret_key }
    end
  end
end