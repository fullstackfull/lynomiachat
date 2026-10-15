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
# operator override and an integration's bundled grant are both honoured, and the counter is
# taken under `account.lock!` -- the same lock Billing::ResourceLimit#exceeded uses, for the
# same reason. Two senders arriving at `used == limit - 1` would otherwise both read
# `limit - 1`, both decide there was room, and both send.
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
  # CALL IT INSIDE THE CALLER'S TRANSACTION. The lock is released when that transaction ends,
  # and without one the lock is held for a single statement and buys nothing.
  #
  # @return [Integer, nil] the ceiling that was reached, or nil when the send may proceed
  def consume(account, resource = RESOURCE)
    limit = Billing::Entitlements.limit(account, resource)
    return nil if limit.nil?

    account.lock!
    counter = counter_for(account, resource)
    return limit if counter.used >= limit

    # `increment!` deliberately: it issues `UPDATE ... SET used = used + 1`, which is one
    # atomic statement, rather than reading the value into Ruby and writing it back. Skipping
    # validations is the point -- the row was validated when it was created, and re-validating
    # a counter bump buys nothing while turning an atomic update into a read-modify-write.
    counter.increment!(:used) # rubocop:disable Rails/SkipsModelValidations
    nil
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
