require 'rails_helper'

# The global `LYN-` series, proved rather than asserted.
#
# This file opts out of transactional fixtures. Transactional tests put every example on ONE connection inside
# ONE transaction, where a transaction-scoped advisory lock cannot be contended at all: a second "transaction"
# would be a savepoint on the same connection, already holding the lock. So the only way to show that the lock
# does what it is for is a connection per thread, real commits, and a teardown that removes what it committed.
#
# What is measured here, not claimed: every number handed out under parallel load is distinct, the set is
# CONTIGUOUS (no gap that a later reader would read as a deleted ticket), and a second allocator genuinely
# WAITS for the first to commit instead of reading the same MAX.
RSpec.describe PlatformSupport::ReferenceAllocator do
  self.use_transactional_tests = false

  let(:account) { Account.create!(name: "allocator-#{SecureRandom.hex(4)}") }

  after do
    PlatformSupport::Ticket.where(account_id: account.id).delete_all
    Account.where(id: account.id).delete_all
  end

  def open_ticket
    PlatformSupport::Ticket.create!(account_id: account.id, account_name_at_creation: account.name,
                                    reporter_name: 'Allocator proof', subject: 'Allocator proof')
  end

  it 'starts at one on an empty table' do
    expect(described_class.next_reference_number).to eq(PlatformSupport::Ticket.unscoped.count + 1)
  end

  it 'continues from the highest number installation-wide, not per account' do
    other = Account.create!(name: "allocator-other-#{SecureRandom.hex(4)}")
    first = open_ticket
    second = PlatformSupport::Ticket.create!(account_id: other.id, account_name_at_creation: other.name,
                                             reporter_name: 'Other', subject: 'Other account')

    expect(second.reference_number).to eq(first.reference_number + 1)
  ensure
    PlatformSupport::Ticket.where(account_id: other.id).delete_all
    Account.where(id: other.id).delete_all
  end

  it 'takes a different lock namespace from the tenant helpdesk, so the two never contend' do
    namespaces = [described_class::LOCK_NAMESPACE_SQL, Support::Tickets::ReferenceAllocator::LOCK_NAMESPACE_SQL]
    values = namespaces.map { |sql| ActiveRecord::Base.connection.select_value("SELECT #{sql}") }

    expect(values.uniq.length).to eq(2)
  end

  # The load test. `workers` follows the connection pool so this is genuinely parallel under any pool size,
  # and the rounds are there because one round can pass by luck.
  it 'hands out no duplicate and leaves no gap under parallel transactions' do
    workers = [ActiveRecord::Base.connection_pool.size - 1, 2].max
    rounds = 8
    allocated = Queue.new

    elapsed = Benchmark.realtime do
      rounds.times do
        Array.new(workers) do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              # Through the model, so what is proved is the production path: the allocator runs in a
              # before_validation inside the creating transaction, which is where the lock has to be held.
              ActiveRecord::Base.transaction { allocated << open_ticket.reference_number }
            end
          end
        end.each(&:join)
      end
    end

    numbers = Array.new(allocated.size) { allocated.pop }
    expect(numbers.length).to eq(workers * rounds)

    # No duplicate: the unique index would have raised, but the point is that it never had to.
    expect(numbers.uniq.length).to eq(numbers.length)
    # No gap: the set is exactly the contiguous run from the lowest number allocated.
    expect(numbers.sort).to eq((numbers.min..numbers.max).to_a)
    # And the rows agree with what the allocator said.
    expect(PlatformSupport::Ticket.where(account_id: account.id).pluck(:reference_number).sort).to eq(numbers.sort)

    Rails.logger.info(
      "platform_support reference allocator: #{numbers.length} allocations by #{workers} threads " \
      "over #{rounds} rounds in #{(elapsed * 1000).round(1)}ms, " \
      "range #{numbers.min}..#{numbers.max}, duplicates #{numbers.length - numbers.uniq.length}"
    )
  end

  # Serialisation, shown directly rather than inferred from the absence of a collision: the second connection
  # cannot read MAX until the first commits, so it cannot read the same MAX.
  it 'makes a second allocator wait for the first transaction to commit' do
    holder_ready = Queue.new
    release_holder = Queue.new
    second_number = Queue.new
    first_number = Queue.new

    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          first_number << open_ticket.reference_number
          holder_ready << true
          release_holder.pop
        end
      end
    end

    holder_ready.pop
    waiter = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction { second_number << open_ticket.reference_number }
      end
    end

    # The waiter is blocked on pg_advisory_xact_lock, not merely slow: it cannot finish while the holder's
    # transaction is open.
    expect(waiter.join(0.5)).to be_nil

    waited = Benchmark.realtime do
      release_holder << true
      [holder, waiter].each(&:join)
    end

    first = first_number.pop
    second = second_number.pop
    expect(second).to eq(first + 1)
    Rails.logger.info("platform_support reference allocator: waiter released in #{(waited * 1000).round(1)}ms")
  end
end
