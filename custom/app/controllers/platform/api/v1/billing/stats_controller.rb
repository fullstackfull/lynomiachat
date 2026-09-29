# frozen_string_literal: true

class Platform::Api::V1::Billing::StatsController < Platform::Api::V1::Billing::BaseController
  LIVE_STATUSES = %w[trialing active past_due].freeze

  # GET /platform/api/v1/billing/stats
  def show
    subscriptions = BillingSubscription.all
    usable = subscriptions.includes(:plan).count(&:usable?)

    render_data(
      {
        total_accounts: Account.count,
        usable_accounts: usable,
        locked_accounts: subscriptions.count - usable,
        by_status: subscriptions.group(:status).count,
        by_source: subscriptions.group(:source).count,
        by_plan: BillingPlan.ordered.map do |plan|
          { id: plan.id, name: plan.name, active: plan.active, subscribers: plan.subscriptions.where(status: LIVE_STATUSES).count }
        end,
        trials_ending_in_7_days: subscriptions.where(status: 'trialing', trial_ends_at: Time.current..7.days.from_now).count,
        mrr: monthly_recurring_revenue
      }
    )
  end

  private

  # Estimated monthly revenue of paying Stripe subscriptions, per currency,
  # based on the plans' current prices (yearly plans divided by 12).
  def monthly_recurring_revenue
    totals = Hash.new(0)
    BillingSubscription.includes(:plan)
                       .where(source: 'stripe', status: %w[active past_due])
                       .where.not(stripe_subscription_id: nil)
                       .find_each do |subscription|
      plan = subscription.plan
      next if plan.nil?

      monthly_cents = plan.interval == 'year' ? plan.price_cents / 12.0 : plan.price_cents
      totals[plan.currency] += monthly_cents * subscription.quantity
    end
    totals.transform_values { |cents| (cents / 100.0).round(2) }
  end
end
