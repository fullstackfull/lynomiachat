# frozen_string_literal: true

# How much of a METERED allowance an account has used in the current period (P5G).
#
# THE COUNTERS IN Billing::ResourceLimit::COUNTS ANSWER A DIFFERENT QUESTION. They count rows
# that exist -- agents, inboxes, stores, flows -- so "how many do you have" and "how many have
# you used" are the same number and deleting one gives it back. A send is not like that: a
# message sent is spent, and the allowance refills when the period turns over rather than when
# anything is deleted. That is why this is a stored counter and not a query.
#
# THE PERIOD IS THE SUBSCRIPTION'S, WHEN THERE IS ONE. A merchant billed on the 7th should get
# their allowance back on the 7th, not on the 1st; anchoring to the calendar month would give
# a week of every cycle away or take it. With no subscription -- an account entitled through
# an integration's bundled package, which is every Store Syria merchant -- the calendar month
# is the only honest anchor this side knows, and it is used.
class BillingUsageCounter < ApplicationRecord
  self.table_name = 'billing_usage_counters'

  belongs_to :account

  validates :resource, presence: true, inclusion: { in: BillingPlan::LIMIT_KEYS }
  validates :period_start, presence: true

  scope :for_period, ->(account, resource, period) { where(account: account, resource: resource.to_s, period_start: period) }

  # WHEN THE CURRENT PERIOD BEGAN.
  #
  # Derived from the subscription's `current_period_end` by stepping one month back, because
  # that is the field the billing provider actually maintains -- there is no period_start
  # column to read and inventing one would be a second thing to keep in sync with the
  # provider.
  #
  # A SUBSCRIPTION WHOSE END HAS PASSED KEEPS ANCHORING THE PERIOD, and the earlier version
  # of this switched to the calendar month instead. That was a hole in a ceiling that is
  # supposed to fail closed: between a period ending and the provider writing the next one,
  # the anchor moved, which is a NEW counter row, which is a FRESH ALLOWANCE. A merchant at
  # their limit got a second one in the renewal gap and a third when the renewal landed. The
  # window is short but it is exactly the window a runaway campaign is in -- the account is
  # at its ceiling, which is why it is being refused at all.
  #
  # So a stale end is kept. The allowance refills when the provider renews, and until it
  # does the merchant has the one they were sold. The calendar month remains for an account
  # with NO subscription at all -- every Store Syria merchant, entitled through the
  # integration's bundled package -- because it is the only anchor this side knows for them.
  #
  # IN UTC, BECAUSE THIS VALUE IS PART OF A UNIQUE KEY AND MUST NOT DEPEND ON WHO IS ASKING.
  # `Time.zone` is thread-local. Read through it, `current_period_end` is converted to the
  # CALLING THREAD's zone before `.to_date` truncates it, so the same subscription anchors two
  # different periods for two callers whose zones straddle midnight -- and `period_start` is
  # the third column of index_billing_usage_counters_on_scope. Two values mean two counter
  # rows, which means two full allowances on a ceiling whose whole purpose is to fail closed,
  # and a usage display reading a row the sender never writes to.
  #
  # Nothing in this application sets `Time.zone` per request or per job today -- the reporting
  # code converts with `in_time_zone` and leaves the thread-local alone -- so no shipped caller
  # diverges. But the per-user `Time.use_zone` around_action is the ordinary Rails idiom for
  # exactly this app's "show me my hours in my timezone" surface, and a key derived from
  # ambient state is wrong the day somebody adds it rather than the day it is written. The
  # stored column is UTC; deriving the key from it directly is also one character shorter than
  # deriving it from the reader.
  # ONLY A LIVE PROVIDER CYCLE ANCHORS THE PERIOD. Everything else -- an operator's comp, a
  # trial, a cancelled subscription, an account with none at all -- takes the calendar
  # month, because none of them has a cycle anybody is going to advance.
  #
  # A MANUAL GRANT'S `current_period_end` IS AN EXPIRY, NOT A CYCLE END. nil is a supported
  # state with its own Super Admin copy ("Plan X granted with no end date") and is the
  # default of `Billing::AdminActions#grant_plan`, so a comp starts on the calendar month.
  # The moment an operator re-granted the same plan WITH an expiry -- an ordinary tidying-up,
  # not a renewal -- the anchor jumped to (expiry - 1 month), which for a comp running to the
  # end of the year is a date in the FUTURE and in any case a different counter key: a full
  # fresh allowance in the same calendar month, reissuable by toggling the expiry.
  #
  # TESTING `manual?` WAS NOT ENOUGH, and that is why this reads the STATUS as well. `source`
  # is a mutable column recording who wrote the row, not whether a cycle is running, and one
  # shipped operator action flips it: `extend_trial` writes `source: 'stripe'` and
  # `status: 'trialing'` while deliberately leaving `current_period_end` alone, so clicking
  # "Extend trial" on a comp that has an expiry moved the anchor and handed out the whole
  # allowance again -- the same defect through a different button. The mirror case is a
  # subscription the provider has finished with: a `canceled` row keeps a
  # `current_period_end` nothing will ever advance, so an account still entitled through a
  # Store Syria bundled grant was pinned to one dead period forever and never refilled.
  #
  # `past_due` anchors with `active` on purpose: the provider still owns that cycle and will
  # advance it on payment, and the alternative -- the calendar month -- would hand a merchant
  # who has not paid a fresh allowance, which is the wrong direction for a ceiling that is
  # supposed to fail closed.
  CYCLED_STATUSES = %w[active past_due].freeze

  def self.period_start_for(account)
    ends_at = provider_cycle_end(account.billing_subscription)
    return Time.now.utc.to_date.beginning_of_month if ends_at.nil?

    (ends_at.utc - 1.month).to_date
  end

  def self.provider_cycle_end(subscription)
    return nil if subscription.nil? || subscription.manual?
    return nil unless CYCLED_STATUSES.include?(subscription.status)

    subscription.current_period_end
  end
end
