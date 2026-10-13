require 'rails_helper'

# The sweep stamps breaches, writes the two `sla_*` events, and is idempotent because the partial-index
# predicate excludes a row whose breach is already recorded.
#
# Synthetic numbers only: the due times are set directly here, so no threshold value is involved at all.
RSpec.describe PlatformSupport::Sla::Sweeper do
  let(:account) { create(:account) }
  let(:policy) do
    PlatformSupport::SlaPolicy.create!(name: 'Synthetic', first_response_time_threshold: 60,
                                       resolution_time_threshold: 180)
  end
  let(:now) { Time.zone.parse('2026-03-05 09:00:00 UTC') }

  def ticket(**attributes)
    create(:platform_support_ticket, account: account, sla_policy: policy, **attributes)
  end

  describe 'first response' do
    it 'stamps the breach and writes sla_first_response_breached once the target has passed' do
      record = ticket(first_response_due_at: now - 1.second)

      expect { described_class.new(now: now).perform }.to change { record.reload.first_response_breached_at }.from(nil)

      expect(record.events.pluck(:event_type)).to eq(['sla_first_response_breached'])
      expect(record.events.first.actor_type).to eq('System')
    end

    it 'leaves a ticket whose target has not passed alone' do
      record = ticket(first_response_due_at: now + 1.second)

      described_class.new(now: now).perform

      expect(record.reload.first_response_breached_at).to be_nil
      expect(record.events).to be_empty
    end

    it 'leaves a ticket that already answered alone' do
      record = ticket(first_response_due_at: now - 1.hour, first_responded_at: now - 2.hours)

      described_class.new(now: now).perform

      expect(record.reload.first_response_breached_at).to be_nil
    end
  end

  describe 'resolution' do
    it 'stamps the breach and writes sla_resolution_breached' do
      record = ticket(resolution_due_at: now - 1.second)

      described_class.new(now: now).perform

      expect(record.reload.resolution_breached_at).to eq(now)
      expect(record.events.pluck(:event_type)).to eq(['sla_resolution_breached'])
    end
  end

  # `status < 4` is why resolved and closed are numbered last. A ticket that is done cannot breach afterwards.
  it 'ignores resolved and closed tickets' do
    [:resolved, :closed].each do |status|
      ticket(status: status, resolution_due_at: now - 1.hour, first_response_due_at: now - 1.hour)
    end

    counts = described_class.new(now: now).perform

    expect(counts).to eq(first_response_breached: 0, resolution_breached: 0)
  end

  # A paused ticket cannot breach: the remaining time is not Lynomia's to spend.
  it 'ignores a ticket paused on waiting_on_customer' do
    record = ticket(status: :waiting_on_customer, sla_paused_at: now - 1.minute,
                    resolution_due_at: now - 1.second, first_response_due_at: now - 1.second)

    described_class.new(now: now).perform

    expect(record.reload.resolution_breached_at).to be_nil
    expect(record.first_response_breached_at).to be_nil
  end

  it 'ignores an ungoverned ticket, because it has no due time at all' do
    record = create(:platform_support_ticket, account: account)

    described_class.new(now: now).perform

    expect(record.reload.resolution_breached_at).to be_nil
  end

  # IDEMPOTENT BY CONSTRUCTION, not by a guard: stamping the column removes the row from the index predicate.
  it 'writes nothing on a second run' do
    ticket(first_response_due_at: now - 1.second, resolution_due_at: now - 1.second)
    described_class.new(now: now).perform

    second = described_class.new(now: now + 1.hour)

    expect { second.perform }.not_to change(PlatformSupport::Event, :count)
    expect(second.perform).to eq(first_response_breached: 0, resolution_breached: 0)
  end

  # `metadata` is never serialized to the tenant, and it carries nothing but timestamps: no body, no provider
  # payload, no credential (03-authorization-security.md §11).
  it 'writes only timestamps into event metadata' do
    record = ticket(resolution_due_at: now - 1.second, description: 'a secret-looking description')

    described_class.new(now: now).perform

    expect(record.events.first.metadata.keys).to contain_exactly('due_at', 'breached_at')
  end

  # Every sla_* type is excluded from the customer-visible allow-list, so a breach is invisible to the tenant.
  it 'writes events the customer-visible allow-list excludes' do
    record = ticket(resolution_due_at: now - 1.second, first_response_due_at: now - 1.second)

    described_class.new(now: now).perform

    expect(record.events.pluck(:event_type) & PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES).to be_empty
  end

  it 'reports what it decided' do
    ticket(first_response_due_at: now - 1.second)
    ticket(resolution_due_at: now - 1.second)

    expect(described_class.new(now: now).perform).to eq(first_response_breached: 1, resolution_breached: 1)
  end

  # The queue is a scheduled read over the working set, not a scan that grows with the table.
  it 'does not grow its query count as decided tickets accumulate' do
    4.times { ticket(status: :closed, resolution_due_at: now - 1.hour) }
    baseline = count_queries { described_class.new(now: now).perform }

    12.times { ticket(status: :closed, resolution_due_at: now - 1.hour) }
    grown = count_queries { described_class.new(now: now).perform }

    expect(grown).to eq(baseline)
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
