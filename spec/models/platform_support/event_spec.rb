require 'rails_helper'

RSpec.describe PlatformSupport::Event do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck')
  end

  it 'declares the eighteen event types V1 recognises' do
    expect(described_class::EVENT_TYPES).to eq(
      %w[created subject_changed category_changed priority_changed status_changed assigned unassigned
         sla_policy_applied sla_first_response_met sla_first_response_breached sla_resolution_breached
         customer_replied operator_replied internal_note_added resolved reopened closed account_deleted]
    )
  end

  it 'has no link event types, because the links table is not created in V1' do
    expect(described_class::EVENT_TYPES.grep(/link/)).to be_empty
  end

  describe 'customer visibility' do
    it 'is a positive allow-list of seven of the eighteen' do
      expect(described_class::CUSTOMER_VISIBLE_EVENT_TYPES).to eq(
        %w[created status_changed customer_replied operator_replied resolved reopened closed]
      )
    end

    it 'hides triage, assignment, the existence of a note, every SLA event and the deletion marker' do
      hidden = described_class::EVENT_TYPES - described_class::CUSTOMER_VISIBLE_EVENT_TYPES

      expect(hidden).to include('assigned', 'unassigned', 'internal_note_added', 'priority_changed',
                                'category_changed', 'subject_changed', 'account_deleted')
      expect(hidden.grep(/\Asla_/).length).to eq(4)
    end

    it 'defaults a newly declared type to hidden, which is the property that matters' do
      expect(described_class::EVENT_TYPES - described_class::CUSTOMER_VISIBLE_EVENT_TYPES).not_to be_empty
      expect(described_class::CUSTOMER_VISIBLE_EVENT_TYPES).not_to include('sla_resolution_breached')
    end

    it 'filters by the allow-list in the query rather than in a view' do
      visible = described_class.create!(ticket: ticket, event_type: 'status_changed')
      hidden = described_class.create!(ticket: ticket, event_type: 'assigned')

      expect(described_class.customer_visible).to include(visible)
      expect(described_class.customer_visible).not_to include(hidden)
    end
  end

  it 'refuses an event type nobody declared' do
    event = described_class.new(ticket: ticket, event_type: 'escalated')
    expect(event).not_to be_valid
    expect(event.errors[:event_type]).to be_present
  end

  it 'allows the same three actor parties as the thread, and no others' do
    expect(described_class::ACTOR_TYPES).to eq(PlatformSupport::Message::AUTHOR_TYPES)

    event = described_class.new(ticket: ticket, event_type: 'created', actor_type: 'Contact')
    expect(event).not_to be_valid
  end

  describe '#customer_visible_actor_name' do
    it 'names the customer on their own action' do
      event = described_class.create!(ticket: ticket, event_type: 'customer_replied',
                                      actor_type: 'User', actor_id: reporter.id, actor_name: 'Hisham')

      expect(event.customer_visible_actor_name).to eq('Hisham')
    end

    it 'names nobody on an operator action, so no individual is ever surfaced' do
      event = described_class.create!(ticket: ticket, event_type: 'operator_replied',
                                      actor_type: 'PlatformSupport::Agent', actor_id: 1, actor_name: 'Operator One')

      expect(event.customer_visible_actor_name).to be_nil
    end

    it 'names nobody on a machine action' do
      event = described_class.create!(ticket: ticket, event_type: 'status_changed', actor_type: 'System')

      expect(event.customer_visible_actor_name).to be_nil
    end
  end

  it 'defaults metadata to an empty hash and is written once, with no updated_at' do
    event = described_class.create!(ticket: ticket, event_type: 'created')

    expect(event.metadata).to eq({})
    expect(described_class.column_names).not_to include('updated_at')
  end
end
