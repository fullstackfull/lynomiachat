require 'rails_helper'

# TWO WORKERS, ONE ALLOWANCE. The property a HARD ceiling is worthless without.
#
# Billing::MeteredUsage is the commercial quota, and the one thing it promises that the pacing
# beside it does not is that it FAILS CLOSED -- "this plan allows N sends this period" has to
# mean N, not N plus however many Sidekiq workers happened to be running. The scheduler
# enqueues one job per due campaign every five minutes, so an account with two active
# campaigns has two workers in the send loop at once, each calling `consume` per recipient.
# That is the ordinary production shape, not a contrived one.
#
# Nothing in a single-threaded example can tell whether the protection is a real row lock or a
# check that happens to run first. So this file opts out of transactional fixtures -- under
# them every thread shares one connection inside one transaction and cannot contend for a lock
# at all -- takes a connection per thread, and removes what it commits.
RSpec.describe Billing::MeteredUsage, type: :model do
  self.use_transactional_tests = false

  # FOUR, BECAUSE THE DEFAULT CONNECTION POOL IS FIVE and the example's own setup holds one of
  # them. A spec that needs RAILS_MAX_THREADS raised to pass is a spec that fails in CI. Four
  # contending workers demonstrate the property exactly as six do: without a lock spanning the
  # read and the write, every one of them gets through a ceiling of one.
  #
  # A local rather than a constant: a constant assigned inside this block would land on Object.
  workers = 4

  let(:account) { Account.create!(name: "quota-concurrency-#{SecureRandom.hex(4)}") }
  let(:plan) { BillingPlan.create!(name: "quota-#{SecureRandom.hex(4)}", limits: { 'campaign_sends' => 1 }) }

  before do
    allow(Billing::Settings).to receive(:enforced?).and_return(true)
    subscription = account.billing_subscription || BillingSubscription.new(account: account, source: 'manual')
    subscription.update!(plan: plan, status: 'active', current_period_end: 20.days.from_now)
    account.reload
  end

  after do
    BillingUsageCounter.where(account_id: account.id).delete_all
    BillingSubscription.where(account_id: account.id).delete_all
    Custom::AuditLog.where(associated_type: 'Account', associated_id: account.id).delete_all
    Account.where(id: account.id).delete_all
    BillingPlan.where(id: plan.id).delete_all
  end

  # THE WINDOW IS FORCED RATHER THAN RACED FOR. Releasing six threads at `consume` and hoping
  # they interleave is a coin toss that would pass on a fast machine and fail in CI, which is
  # the worst kind of concurrency test. The barrier instead parks every thread at exactly the
  # point after the counter row has been fetched and immediately before the read-compare-
  # increment, which is the window the ceiling either closes or does not. A guard that holds a
  # lock across that window serialises them; one that does not lets all six through.
  def consume_concurrently(workers)
    barrier = Concurrent::CyclicBarrier.new(workers)
    allow(described_class).to receive(:counter_for).and_wrap_original do |original, *args|
      original.call(*args).tap { barrier.wait(10) }
    end

    Array.new(workers) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { described_class.consume(Account.find(account.id)) }
      end
    end.map(&:value)
  end

  it 'lets exactly one send through when four workers reach a ceiling of one together' do
    outcomes = consume_concurrently(workers)

    expect(outcomes.count(nil)).to eq(1)
    expect(outcomes.count(1)).to eq(workers - 1)
  end

  # AND THE LEDGER AGREES WITH WHAT WAS ALLOWED. A ceiling that refuses correctly but
  # miscounts is the same defect one period later, when the merchant is refused sends they
  # never made.
  it 'records exactly one unit of usage' do
    consume_concurrently(workers)

    expect(described_class.usage(account)[:used]).to eq(1)
  end
end
