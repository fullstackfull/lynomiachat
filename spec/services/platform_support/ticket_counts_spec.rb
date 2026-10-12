require 'rails_helper'

RSpec.describe PlatformSupport::TicketCounts do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:scope) { PlatformSupport::Ticket.where(account_id: account.id) }

  def open_ticket(status:, **attributes)
    PlatformSupport::Ticket.create!(
      { account: account, account_name_at_creation: account.name, reporter: reporter,
        reporter_name: reporter.available_name, subject: "#{status} ticket", status: status }.merge(attributes)
    )
  end

  it 'answers zeroes for an account with no tickets' do
    expect(described_class.new(scope: scope).call).to eq(open: 0, closed: 0, unread: 0)
  end

  it 'counts the four open statuses as open and the two terminal ones as closed' do
    PlatformSupport::Ticket::OPEN_STATUSES.each { |status| open_ticket(status: status) }
    PlatformSupport::Ticket::CLOSED_STATUSES.each { |status| open_ticket(status: status) }

    expect(described_class.new(scope: scope).call).to include(open: 4, closed: 2)
  end

  it 'counts an unread ticket by the derived predicate, with no stored flag to keep in step' do
    open_ticket(status: 'open', last_operator_message_at: Time.current)
    open_ticket(status: 'open', last_operator_message_at: 2.hours.ago, customer_last_viewed_at: 1.hour.ago)

    expect(described_class.new(scope: scope).call).to include(open: 2, unread: 1)
  end

  # A header reading "12" over a list of 3 would be a disclosure, not a cosmetic bug.
  it 'describes only what the caller\'s own scope contains' do
    open_ticket(status: 'open')
    other = create(:account)
    PlatformSupport::Ticket.create!(account: other, account_name_at_creation: other.name,
                                    reporter_name: 'Somebody', subject: 'Another account')

    expect(described_class.new(scope: scope).call).to include(open: 1)
  end

  it 'costs two queries whatever the number of tickets, because the status counts are grouped' do
    5.times { open_ticket(status: 'open', last_operator_message_at: Time.current) }

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      described_class.new(scope: scope).call
    end

    expect(queries).to eq(2)
  end
end
