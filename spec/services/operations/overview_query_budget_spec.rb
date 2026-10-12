require 'rails_helper'

# The Operations front page is what an operator refreshes while something is wrong, so its cost must not follow
# the size of the installation. It did: docs/product-refinement/MERGE_GATE.md §V3 measured 620 queries with a
# warm derived cache against 200 inactive subscriptions, because whether billing is enforced -- an
# installation-wide question, three installation_configs reads -- was asked once per candidate, and this block
# sits outside that cache.
RSpec.describe Operations::Overview do
  let(:plan) { create(:billing_plan) }

  it 'does not grow its query count as lockable subscriptions grow' do
    seed_lockable(4)
    baseline = count_queries { described_class.new.call }

    seed_lockable(12)
    grown = count_queries { described_class.new.call }

    expect(grown).to be <= baseline + 2
  end

  # The repetition itself, named rather than inferred from a total. Before the fix this was three reads per
  # `inactive` candidate; now it is three for the page.
  it 'reads the installation-wide billing setting once however many subscriptions it judges' do
    seed_lockable(12)

    reads = count_queries(only: 'installation_configs') { Operations::BillingState.new.call }

    expect(reads).to be <= 4
  end

  # `inactive` is the status that reaches the enforcement question (Operations::BillingState#locked_accounts):
  # `usable?` answers from the row for every other status.
  def seed_lockable(count)
    count.times do
      BillingSubscription.create!(account: create(:account), plan: plan, status: 'inactive', source: 'stripe')
    end
  end

  def count_queries(only: nil)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])

      count += 1 if only.nil? || payload[:sql].include?(only)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
