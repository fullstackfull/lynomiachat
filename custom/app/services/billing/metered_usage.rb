# frozen_string_literal: true

# A HARD CEILING ON HOW MANY MESSAGES AN ACCOUNT MAY SEND IN A PERIOD (P5G).
#
# THIS IS NOT THE THROTTLE, AND THE DIFFERENCE IS THE WHOLE REASON IT IS A SEPARATE MODULE.
# docs/partner-consent/THROTTLE-SAFETY.md §1 names the three things people conflate:
#
#   pacing              Campaigns::Throttle. A courtesy ceiling on how fast WE dial. Best
#                       effort, and it FAILS OPEN, because a cache blip must not become an
#                       outage.
#   provider limit      the provider's own 429 and messaging tier. Not ours.
#   commercial quota    HERE. "This plan allows N sends this period." It FAILS CLOSED,
#                       because a quota that fails open is not a quota -- it is a suggestion
#                       that stops applying exactly when the system is under stress, which is
#                       when a runaway campaign is most likely to be the cause.
#
# That note also said this must not be routed through Campaigns::Throttle and must live with
# Billing::ResourceLimit. It does: the ceiling comes from Billing::Entitlements, so an
# operator override and an integration's bundled grant are both honoured, and the unit is
# taken under a row lock held across the read and the write. Two senders arriving at
# `used == limit - 1` would otherwise both read `limit - 1`, both decide there was room, and
# both send. See `consume` for why the lock is the counter's and not the account's.
#
# THE UNIT IS AN ATTEMPT, NOT A DELIVERY, and that is deliberate. A message handed to the
# provider has been spent whatever the provider then does with it: counting only deliveries
# would let a campaign to ten thousand dead numbers consume no quota at all while costing the
# platform ten thousand provider calls. The merchant is told this in the refusal copy rather
# than discovering it from a mismatch between two numbers.
#
# NO CEILING MEANS NO COUNTING. An account whose plan sets no `campaign_sends` limit -- which
# is every account that existed before this -- never touches the table. The feature is
# therefore inert until somebody sells a metered plan, which is what makes it safe to ship
# ahead of the plans that use it.
module Billing::MeteredUsage
  RESOURCE = 'campaign_sends'

  module_function

  # Take one unit of this period's allowance.
  #
  # THE LOCK HAS TO SPAN THE READ AND THE WRITE, AND `with_lock` IS WHAT MAKES IT DO THAT.
  # This first read `account.lock!` and then compared and incremented, which looked like the
  # gate in Billing::ResourceLimit#exceeded and was not one. That method is called from inside
  # a `validate ... on: :create`, so it already runs in the save's transaction and its lock is
  # held to the end of it. Nothing wraps a campaign's send loop in a transaction -- none of
  # the four senders opens one -- so here the `SELECT ... FOR UPDATE` was its own autocommit
  # statement and the row lock was released before the next line ran. Two workers both read
  # `used == limit - 1`, both found room, and both sent. The scheduler enqueues one job per
  # due campaign, so an account with two active campaigns has exactly that shape, and the
  # overshoot grows with the number of workers -- a ceiling that stops applying precisely when
  # it is load-bearing. spec/services/billing/metered_usage_concurrency_spec.rb forces the
  # window rather than racing for it.
  #
  # IT LOCKS THE COUNTER ROW, NOT THE ACCOUNT. That is the row being read and written, it is
  # the narrowest thing that serialises two senders of the same account, and it leaves
  # Billing::ResourceLimit's account lock uncontended. `counter_for` runs OUTSIDE the lock on
  # purpose: its `find_or_create_by!` can raise RecordNotUnique, and a RecordNotUnique inside
  # a transaction poisons it, so its rescue would have nothing to re-read with.
  #
  # @return [Integer, nil] the ceiling that was reached, or nil when the send may proceed
  def consume(account, resource = RESOURCE)
    limit = Billing::Entitlements.limit(account, resource)
    return nil if limit.nil?

    counter = counter_for(account, resource)
    # `with_lock` reloads the row FOR UPDATE inside a transaction, so `used` below is the
    # committed value no other sender can be changing, and it stays that way until the
    # increment commits.
    counter.with_lock do
      next limit if counter.used >= limit

      # `increment!` deliberately: it issues `UPDATE ... SET used = used + 1` rather than
      # writing back a value read into Ruby. Skipping validations is the point -- the row was
      # validated when it was created, and re-validating a counter bump buys nothing.
      counter.increment!(:used) # rubocop:disable Rails/SkipsModelValidations
      nil
    end
  end

  # What the merchant has used and what they are allowed, for a usage display. A read with no
  # lock, so it is a report rather than a gate: `consume` is what refuses.
  def usage(account, resource = RESOURCE)
    limit = Billing::Entitlements.limit(account, resource)
    period = BillingUsageCounter.period_start_for(account)

    { resource: resource, limit: limit, period_start: period,
      used: BillingUsageCounter.for_period(account, resource, period).pick(:used).to_i }
  end

  # The row for this account, resource and period, created on first use.
  #
  # `find_or_create_by` AND a rescue, because the lock above serialises senders of ONE account
  # but the period can also turn over between two accounts' workers, and because a caller that
  # forgot the enclosing transaction would not be serialised at all. The unique index is the
  # real arbiter; the rescue re-reads the row the other writer inserted rather than letting a
  # race become a second counter that silently doubles the allowance.
  def counter_for(account, resource)
    period = BillingUsageCounter.period_start_for(account)
    BillingUsageCounter.find_or_create_by!(account: account, resource: resource.to_s, period_start: period)
  rescue ActiveRecord::RecordNotUnique
    BillingUsageCounter.for_period(account, resource, period).first!
  end
end
