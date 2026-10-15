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
  def self.period_start_for(account)
    ends_at = account.billing_subscription&.current_period_end
    return Time.zone.today.beginning_of_month if ends_at.nil?

    (ends_at - 1.month).to_date
  end
end
