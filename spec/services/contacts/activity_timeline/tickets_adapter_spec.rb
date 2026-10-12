require 'rails_helper'

RSpec.describe Contacts::ActivityTimeline::TicketsAdapter do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:other_contact) { create(:contact, account: account) }

  def visibility_for(user)
    Contacts::ActivityTimeline::Visibility.new(
      user: user, conversations: account.conversations.where(contact_id: contact.id),
      inbox_ids: account.inboxes.select(:id)
    )
  end

  def fetch(user: administrator, limit: 30)
    described_class.new(account: account, contact: contact, visibility: visibility_for(user)).fetch(limit)
  end

  it "returns the contact's case history, newest first" do
    ticket = create(:support_ticket, account: account, contact: contact, title: 'Order never arrived')
    Support::Tickets::EventRecorder.new(ticket: ticket, user: administrator).record('created')
    Support::Tickets::EventRecorder.new(ticket: ticket, user: administrator)
                                   .record('status_changed', data: { from: 'open', to: 'resolved' })

    entries = fetch

    expect(entries.map(&:kind)).to eq(%w[ticket_status_changed ticket_created])
    expect(entries.first.summary).to eq('Order never arrived')
    expect(entries.first.meta).to include(:reference => ticket.reference, 'from' => 'open', 'to' => 'resolved')
  end

  it 'carries the case category rather than overwriting the timeline category' do
    ticket = create(:support_ticket, account: account, contact: contact, category: 'billing')
    Support::Tickets::EventRecorder.new(ticket: ticket).record('created')

    entry = fetch.first

    expect(entry.category).to eq('tickets')
    expect(entry.meta[:ticket_category]).to eq('billing')
  end

  # An internal note is written for colleagues working the case; a timeline is a wider audience.
  it 'says a note was added without emitting its body' do
    ticket = create(:support_ticket, account: account, contact: contact)
    Support::Tickets::EventRecorder.new(ticket: ticket, user: administrator)
                                   .record('note', body: 'Customer threatened to sue')

    entry = fetch.first

    expect(entry.kind).to eq('ticket_note')
    expect(entry.as_json.to_s).not_to include('threatened')
  end

  describe 'visibility' do
    # Cases are not conversations: an agent sees the cases assigned to them, to their team, or that they opened.
    it 'hides the history of a case the caller does not own' do
      someone_elses = create(:support_ticket, account: account, contact: contact, assignee: administrator)
      Support::Tickets::EventRecorder.new(ticket: someone_elses).record('created')
      mine = create(:support_ticket, account: account, contact: contact, assignee: agent)
      Support::Tickets::EventRecorder.new(ticket: mine).record('created')

      expect(fetch(user: agent).map { |entry| entry.meta[:ticket_id] }).to eq([mine.id])
      expect(fetch(user: administrator).map { |entry| entry.meta[:ticket_id] })
        .to contain_exactly(mine.id, someone_elses.id)
    end
  end

  describe 'scoping' do
    it "never returns another contact's or another account's cases" do
      theirs = create(:support_ticket, account: account, contact: other_contact)
      Support::Tickets::EventRecorder.new(ticket: theirs).record('created')
      foreign_contact = create(:contact, account: other_account)
      foreign = create(:support_ticket, account: other_account, contact: foreign_contact)
      Support::Tickets::EventRecorder.new(ticket: foreign).record('created')

      expect(fetch).to be_empty
    end
  end

  it 'reports its source name for the cursor' do
    adapter = described_class.new(account: account, contact: contact, visibility: visibility_for(administrator))

    expect(adapter.source).to eq('tickets')
  end
end
