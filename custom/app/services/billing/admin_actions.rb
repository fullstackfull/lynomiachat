# frozen_string_literal: true

# Administrative actions on an account subscription (used by the Platform API).
# Every method raises Billing::AdminActions::Error with a readable message
# when the action is not allowed.
module Billing
  class AdminActions
    class Error < StandardError; end

    PAID_ERROR = 'This account has a paid Stripe subscription. Cancel it first, or use change_plan.'

    def initialize(subscription)
      @subscription = subscription
    end

    def extend_trial(days)
      days = days.to_i
      raise Error, 'days must be more than 0' unless days.positive?
      raise Error, PAID_ERROR if stripe_paid?

      plan = @subscription.plan || Billing::Settings.trial_plan
      raise Error, 'Choose a trial plan in Billing Settings first' if plan.nil?

      start = [@subscription.trial_ends_at, Time.current].compact.max
      @subscription.update!(
        status: 'trialing', source: 'stripe', plan: plan,
        trial_ends_at: start + days.days, grace_period_ends_at: nil, cancel_at_period_end: false
      )
    end

    def grant_plan(plan, ends_at: nil)
      raise Error, PAID_ERROR if stripe_paid?

      end_time = parse_end_date(ends_at)
      @subscription.update!(
        source: 'manual', status: 'active', plan: plan, current_period_end: end_time,
        trial_ends_at: nil, grace_period_ends_at: nil, cancel_at_period_end: false,
        stripe_subscription_id: nil, stripe_price_id: nil
      )
    end

    def cancel!
      raise Error, 'The subscription is already canceled' if @subscription.status == 'canceled'

      Billing::SubscriptionCanceller.new(@subscription).perform
      @subscription.update!(status: 'canceled', cancel_at_period_end: false, grace_period_ends_at: nil)
    end

    # prorate: true  -> Stripe charges/credits the difference now
    # prorate: false -> no charge now, the new price applies from the next invoice
    def change_plan(plan, prorate: true, proration_date: nil)
      raise Error, 'The account is already on this plan' if @subscription.plan_id == plan.id

      if stripe_paid?
        Billing::PlanChange.new(account: @subscription.account, plan: plan, prorate: prorate)
                           .perform(proration_date: proration_date)
      elsif @subscription.status == 'trialing' || (@subscription.manual? && @subscription.status == 'active')
        @subscription.update!(plan: plan)
      else
        raise Error, 'The account has no active subscription. Use grant_plan or send a checkout_link.'
      end
    end

    private

    def stripe_paid?
      @subscription.source == 'stripe' &&
        @subscription.stripe_subscription_id.present? &&
        %w[active past_due].include?(@subscription.status)
    end

    def parse_end_date(value)
      return nil if value.blank?

      time = Time.zone.parse(value.to_s)&.end_of_day
      raise Error, 'ends_at is not a valid future date (YYYY-MM-DD)' if time.nil? || time.past?

      time
    end
  end
end