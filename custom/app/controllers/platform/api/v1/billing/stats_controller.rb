# frozen_string_literal: true

class Platform::Api::V1::Billing::StatsController < Platform::Api::V1::Billing::BaseController
  LIVE_STATUSES = %w[trialing active past_due].freeze

  # GET /platform/api/v1/billing/stats
  def show
    subscriptions = tenant_subscriptions
    usable = subscriptions.includes(:plan).count(&:usable?)

    render_data(
      {
        total_accounts: Account.tenant.count,
        usable_accounts: usable,
        locked_accounts: subscriptions.count - usable,
        by_status: subscriptions.group(:status).count,
        by_source: subscriptions.group(:source).count,
        by_plan: by_plan(subscriptions),
        trials_ending_in_7_days: subscriptions.where(status: 'trialing', trial_ends_at: Time.current..7.days.from_now).count,
        mrr: monthly_recurring_revenue
      }
    )
  end

  private

  def by_plan(subscriptions)
    live = subscriptions.where(status: LIVE_STATUSES).group(:plan_id).count

    BillingPlan.ordered.map do |plan|
      { id: plan.id, name: plan.name, active: plan.active, subscribers: live.fetch(plan.id, 0) }
    end
  end

  # WHAT THE INSTALLATION SELLS, which is not everything it runs (P6D).
  #
  # Store Syria's own workspace has a real subscription on a real plan, so without this it is
  # counted as a customer in every figure on this page -- the account total, the usable and
  # locked counts, the per-status and per-plan breakdowns, and the MRR. Scoped once here
  # rather than subtracted from each, because a figure added later would quietly be wrong
  # again.
  def tenant_subscriptions
    BillingSubscription.where(account_id: Account.tenant.select(:id))
  end

  # Estimated monthly revenue of paying Stripe subscriptions, per currency,
  # based on the plans' current prices (yearly plans divided by 12).
  def monthly_recurring_revenue
    totals = Hash.new(0)
    tenant_subscriptions.includes(:plan)
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
