require 'rails_helper'

RSpec.describe PlatformSupport::ThreadTotals do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck')
  end
  let(:quiet_ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Nothing said yet')
  end
  let(:log_file) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a log excerpt'), filename: 'log.txt',
                                           content_type: 'text/plain')
  end

  it 'answers an empty hash for no ids rather than running a query' do
    expect(described_class.for_tickets([])).to eq({})
  end

  it 'counts public messages and their attachments per ticket' do
    first = ticket.messages.create!(PlatformSupport::Message.author_attributes_for(reporter).merge(body: 'Hello'))
    first.platform_support_message_files.attach(log_file)
    ticket.messages.create!(PlatformSupport::Message.author_attributes_for(agent).merge(body: 'Looking'))

    totals = described_class.for_tickets([ticket.id, quiet_ticket.id])

    expect(totals[ticket.id]).to eq(messages: 2, attachments: 1)
    expect(totals[quiet_ticket.id]).to eq(messages: 0, attachments: 0)
  end

  it 'reads a missing id as an empty thread rather than raising' do
    expect(described_class.for_ticket({}, 123)).to eq(messages: 0, attachments: 0)
  end

  # Internal notes and their files are not filtered out of these numbers; they are never joined, so the count
  # cannot disclose that a note exists.
  it 'counts neither internal notes nor their attachments' do
    note = PlatformSupport::InternalNote.create!(ticket: ticket, agent: agent, body: 'Internal')
    note.platform_support_note_files.attach(log_file)

    expect(described_class.for_tickets([ticket.id])[ticket.id]).to eq(messages: 0, attachments: 0)
  end

  it 'costs two queries for a whole page, however many tickets are on it' do
    tickets = Array.new(5) do |index|
      row = PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                            reporter: reporter, reporter_name: reporter.available_name,
                                            subject: "Ticket #{index}")
      row.messages.create!(PlatformSupport::Message.author_attributes_for(reporter).merge(body: 'Hello'))
      row
    end

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      described_class.for_tickets(tickets.map(&:id))
    end

    expect(queries).to eq(2)
  end
end
