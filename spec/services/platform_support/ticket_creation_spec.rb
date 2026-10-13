require 'rails_helper'

RSpec.describe PlatformSupport::TicketCreation do
  let(:plan) { create(:billing_plan, name: 'Growth') }
  let(:account) { create(:account, name: 'Premier Care') }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let!(:subscription) { create(:billing_subscription, account: account, plan: plan, status: 'past_due') }

  let(:attributes) do
    { category: 'whatsapp', subject: 'Template stuck in review', description: 'Submitted on Sunday, still pending.',
      priority: 'high' }
  end

  let(:ticket) { described_class.new(account: account, reporter: reporter, attributes: attributes).perform }

  it 'opens the ticket, numbers it and starts it open at the requested priority' do
    expect(ticket).to have_attributes(status: 'open', priority: 'high', category: 'whatsapp')
    expect(ticket.reference).to match(/\ALYN-\d{6}\z/)
  end

  it 'takes the account and reporter snapshots that survive deletion' do
    expect(ticket).to have_attributes(account_name_at_creation: 'Premier Care',
                                      reporter_name: reporter.available_name)
  end

  it 'takes the commercial snapshot, because a complaint raised while past due reads differently later' do
    expect(ticket).to have_attributes(plan_id_at_creation: plan.id, plan_name_at_creation: 'Growth',
                                      subscription_status_at_creation: 'past_due')
    expect(subscription).to be_present
  end

  it 'snapshots the plan name so renaming the plan afterwards does not rewrite history' do
    ticket
    plan.update!(name: 'Growth (retired)')

    expect(ticket.reload.plan_name_at_creation).to eq('Growth')
  end

  it 'leaves the snapshot empty for an account with no subscription' do
    bare = create(:account)
    bare_reporter = create(:user, account: bare, role: :administrator)
    created = described_class.new(account: bare, reporter: bare_reporter, attributes: attributes).perform

    expect(created).to have_attributes(plan_id_at_creation: nil, plan_name_at_creation: nil,
                                       subscription_status_at_creation: nil)
  end

  it 'opens the thread with the customer\'s own words, so an operator reads one chronological list' do
    expect(ticket.messages.count).to eq(1)
    expect(ticket.messages.first).to have_attributes(author_type: 'User', author_id: reporter.id,
                                                     body: 'Submitted on Sunday, still pending.')
    expect(ticket.last_customer_message_at).to be_present
  end

  it 'records the opening once, and does not also record a reply at the same second' do
    expect(ticket.events.pluck(:event_type)).to eq(['created'])
    expect(ticket.events.first.metadata).to eq('category' => 'whatsapp', 'priority' => 'high', 'status' => 'open')
  end

  it 'attributes the opening event to the reporter' do
    expect(ticket.events.first).to have_attributes(actor_type: 'User', actor_id: reporter.id,
                                                   actor_name: reporter.available_name)
  end

  it 'promises nothing while no policy row exists, which is the state of this installation today' do
    expect(ticket).to have_attributes(sla_policy_id: nil, first_response_due_at: nil, resolution_due_at: nil)
  end

  it 'leaves the ticket unassigned and never creates an account membership for staff' do
    expect(ticket.assignee_id).to be_nil
    expect(AccountUser.where(account_id: account.id).count).to eq(1)
  end

  it 'writes no audit row: a customer opening a ticket is not operator activity' do
    expect { ticket }.not_to change(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket'), :count)
  end

  # THE SLA, ONCE A POLICY EXISTS. The thresholds below are the factory's obviously synthetic seconds; no
  # production target value lives anywhere in this repository (D-7).
  describe 'with a policy on the installation' do
    let!(:default_policy) { create(:platform_support_sla_policy) }

    it 'attaches it, sets both due times from the moment the ticket opened, and records that it did' do
      expect(ticket.sla_policy_id).to eq(default_policy.id)
      expect(ticket.first_response_due_at).to eq(ticket.created_at + 60.seconds)
      expect(ticket.resolution_due_at).to eq(ticket.created_at + 180.seconds)
    end

    # The system, not the reporter: the customer asked for a ticket, not for a target.
    it 'files the sla_policy_applied event as the system, and keeps it away from the customer' do
      applied = ticket.events.find_by(event_type: 'sla_policy_applied')

      expect(applied).to have_attributes(actor_type: 'System', actor_id: nil)
      expect(applied.metadata['sla_policy_id']).to eq(default_policy.id)
      expect(PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES).not_to include('sla_policy_applied')
    end

    it 'prefers the policy bought with the plan over the installation default' do
      for_plan = create(:platform_support_sla_policy, billing_plan_id: plan.id, first_response_time_threshold: 30)

      expect(ticket.sla_policy_id).to eq(for_plan.id)
      expect(ticket.first_response_due_at).to eq(ticket.created_at + 30.seconds)
    end
  end

  # Enqueued, not delivered: a mail job that ran before this transaction committed would be an email about a
  # ticket the database does not have.
  it 'tells the customer and the desk, each through its own message' do
    expect { ticket }.to have_enqueued_mail(PlatformSupport::TicketMailer, :ticket_created)
      .and have_enqueued_mail(PlatformSupport::TicketMailer, :new_ticket)
  end

  it 'rolls the whole thing back when the thread cannot be opened' do
    expect do
      described_class.new(account: account, reporter: reporter,
                          attributes: attributes.merge(description: nil)).perform
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(PlatformSupport::Ticket.count).to eq(0)
  end
end
