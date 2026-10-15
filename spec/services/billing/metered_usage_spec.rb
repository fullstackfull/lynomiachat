require 'rails_helper'

# A HARD SEND CEILING (P5G), and the property that distinguishes it from the pacing beside it.
#
# docs/partner-consent/THROTTLE-SAFETY.md §1 required that a commercial quota must NOT be
# routed through Campaigns::Throttle, because that module fails OPEN -- and a quota that fails
# open is not a quota. These examples pin both halves: the ceiling refuses, and it refuses
# under conditions where the pacing would have let the send through.
RSpec.describe Billing::MeteredUsage do
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan, limits: { 'campaign_sends' => 3 }) }

  # UPDATED, NOT CREATED. An account arrives with a subscription of its own (the trial
  # starter), and `billing_subscriptions.account_id` is unique -- creating a second one fails
  # validation rather than replacing the first, which is how this helper came to exist.
  def subscribe(current_plan = plan, period_end: 20.days.from_now)
    existing = account.billing_subscription || BillingSubscription.new(account: account, source: 'manual')
    existing.update!(plan: current_plan, status: 'active', current_period_end: period_end)
    account.reload
    existing
  end

  before { allow(Billing::Settings).to receive(:enforced?).and_return(true) }

  describe '.consume' do
    # AN ACCOUNT WITH NO CEILING NEVER TOUCHES THE TABLE, which is every account that existed
    # before this and is what makes the feature inert until somebody sells a metered plan.
    it 'is inert when the plan sets no allowance' do
      subscribe(create(:billing_plan, limits: {}))

      expect(described_class.consume(account)).to be_nil
      expect(BillingUsageCounter.count).to eq(0)
    end

    it 'lets a send through while there is allowance left, and counts it' do
      subscribe

      expect(described_class.consume(account)).to be_nil
      expect(described_class.usage(account)[:used]).to eq(1)
    end

    it 'refuses once the allowance is spent, and says what the ceiling was' do
      subscribe
      3.times { described_class.consume(account) }

      expect(described_class.consume(account)).to eq(3)
    end

    # A refused send must not also consume. Otherwise a merchant at their ceiling has their
    # NEXT period eaten by the campaign that was already being refused.
    it 'does not spend a unit on a send it refused' do
      subscribe
      3.times { described_class.consume(account) }

      described_class.consume(account)

      expect(described_class.usage(account)[:used]).to eq(3)
    end

    it 'counts one row per account, resource and period' do
      subscribe
      2.times { described_class.consume(account) }

      expect(BillingUsageCounter.count).to eq(1)
    end

    # The ceiling comes from Billing::Entitlements, so an operator's override reaches it --
    # the property that makes a quota adjustable without editing a plan every merchant shares.
    it 'follows an operator override rather than the plan' do
      subscribe
      create(:billing_entitlement_override, account: account, kind: :limit, name: 'campaign_sends', limit_value: 1)

      expect(described_class.consume(account)).to be_nil
      expect(described_class.consume(account)).to eq(1)
    end
  end

  describe 'the period' do
    it 'is anchored to the subscription, so the allowance refills on the billing date' do
      subscribe(plan, period_end: Date.new(2026, 11, 7).to_time)

      expect(BillingUsageCounter.period_start_for(account)).to eq(Date.new(2026, 10, 7))
    end

    # Every Store Syria merchant is entitled through a bundled package and has no Lynomia
    # subscription, so the calendar month is the only anchor this side knows.
    it 'falls back to the calendar month with no subscription' do
      expect(BillingUsageCounter.period_start_for(account)).to eq(Time.now.utc.to_date.beginning_of_month)
    end

    # A PERIOD END THAT HAS PASSED STILL ANCHORS THE PERIOD, which is the opposite of what
    # this did. Switching to the calendar month while the provider had not yet written the
    # next period MOVED the anchor, and a moved anchor is a new counter row, which is a
    # fresh allowance. A merchant at their ceiling got a second one in the renewal gap and a
    # third when the renewal landed -- in exactly the window where the only reason they are
    # being refused is that they are at the ceiling.
    it 'keeps anchoring to a period end that has already passed, rather than refilling early' do
      subscribe(plan, period_end: 2.months.ago)

      expect(BillingUsageCounter.period_start_for(account)).to eq((2.months.ago.utc - 1.month).to_date)
    end

    it 'does not hand out a second allowance while a renewal is late' do
      subscribe(plan, period_end: 1.minute.ago)
      3.times { described_class.consume(account) }

      expect(described_class.consume(account)).to eq(3)
      expect(described_class.usage(account)[:used]).to eq(3)
    end

    # THE RENEWAL IS WHAT REFILLS IT, NOT THE CALENDAR. Time passing is not a renewal: the
    # allowance moves when the provider writes the next `current_period_end`, which is the
    # same moment the merchant is billed for it.
    it 'starts a fresh allowance when the subscription renews' do
      subscribe(plan, period_end: 5.days.from_now)
      3.times { described_class.consume(account) }
      expect(described_class.consume(account)).to eq(3)

      subscribe(plan, period_end: 35.days.from_now)

      expect(described_class.consume(account)).to be_nil
    end

    # Last period's number is what a merchant disputing a bill, and an operator asked why a
    # campaign stopped, both need.
    it 'keeps the previous period rather than resetting the row' do
      subscribe(plan, period_end: 5.days.from_now)
      described_class.consume(account)

      subscribe(plan, period_end: 35.days.from_now)
      described_class.consume(account)

      expect(BillingUsageCounter.where(account: account).count).to eq(2)
    end

    # ONE SUBSCRIPTION ANCHORS ONE PERIOD, NOT ONE PER READER.
    #
    # `period_start` is the third column of index_billing_usage_counters_on_scope, and this
    # used to derive it through `Time.zone` -- which is a THREAD-LOCAL. Two callers whose
    # zones straddle midnight read the same `current_period_end` as two different dates, and
    # two dates are two counter rows: two full allowances on a ceiling whose entire purpose is
    # to fail closed, plus a usage display reading a row the sender never writes to.
    #
    # The full sweep is what found it. spec/models/working_hour_spec sets
    # `Time.zone = 'Australia/Sydney'` and never puts it back, so from that file onward the
    # main thread asked this question in a different zone from the worker threads in
    # metered_usage_concurrency_spec -- whose ledger assertion then read zero, because the row
    # the workers had incremented was keyed a day away from the one the assertion looked up.
    #
    # 23:30 UTC is 10:30 the NEXT DAY in Sydney, so the two readings fall on different dates
    # unless the derivation ignores the reader entirely.
    it 'anchors the same period whatever zone the caller reads it in' do
      travel_to(Time.utc(2026, 11, 4, 23, 30)) do
        subscribe(plan, period_end: Time.utc(2026, 11, 20, 23, 30))
        utc = Time.use_zone('UTC') { BillingUsageCounter.period_start_for(account.reload) }
        sydney = Time.use_zone('Australia/Sydney') { BillingUsageCounter.period_start_for(account.reload) }

        expect(utc).to eq(Date.new(2026, 10, 20))
        expect(sydney).to eq(utc)
      end
    end

    # The same property on the other branch, where the anchor is the calendar month -- and a
    # month boundary is where that branch diverges: at 23:30 UTC on the 31st it is already
    # November in Sydney.
    it 'anchors the same calendar month whatever zone the caller reads it in' do
      travel_to(Time.utc(2026, 10, 31, 23, 30)) do
        utc = Time.use_zone('UTC') { BillingUsageCounter.period_start_for(account) }
        sydney = Time.use_zone('Australia/Sydney') { BillingUsageCounter.period_start_for(account) }

        expect(utc).to eq(Date.new(2026, 10, 1))
        expect(sydney).to eq(utc)
      end
    end
  end

  describe '.usage' do
    it 'reports the ceiling and what is left of it' do
      subscribe
      2.times { described_class.consume(account) }

      expect(described_class.usage(account)).to include(resource: 'campaign_sends', limit: 3, used: 2)
    end

    it 'reports nothing used before anything is sent' do
      subscribe

      expect(described_class.usage(account)).to include(limit: 3, used: 0)
    end
  end
end
