require 'rails_helper'

RSpec.describe Analytics::Tickets::Metrics do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  # 22:00 UTC on 30 September is 1 October in Kuwait, so a case opened then belongs to this range.
  let(:inside) { Time.utc(2026, 10, 2, 10, 0) }
  let(:edge_inside) { Time.utc(2026, 9, 30, 22, 0) }
  let(:outside) { Time.utc(2026, 9, 30, 20, 0) }
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-07', group_by: 'day')
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :tickets, params: filters)
    )
  end

  describe 'counts' do
    it 'counts cases opened inside the account-timezone window' do
      create(:support_ticket, account: account, created_at: inside)
      create(:support_ticket, account: account, created_at: edge_inside)
      create(:support_ticket, account: account, created_at: outside)

      expect(metrics.tickets_created).to eq(2)
    end

    it 'counts resolutions on when they were resolved, not when they were opened' do
      create(:support_ticket, account: account, created_at: outside, status: :resolved, resolved_at: inside)
      create(:support_ticket, account: account, created_at: inside, status: :open)

      expect(metrics.tickets_resolved).to eq(1)
    end

    # From the durable event trail, so a case reopened and resolved again is still counted.
    it 'counts reopens from the event trail rather than the current status' do
      ticket = create(:support_ticket, account: account, created_at: inside, status: :resolved)
      Support::TicketEvent.create!(account_id: account.id, support_ticket: ticket, event_type: 'reopened',
                                   created_at: inside)
      Support::TicketEvent.create!(account_id: account.id, support_ticket: ticket, event_type: 'reopened',
                                   created_at: outside)

      expect(metrics.tickets_reopened).to eq(1)
    end

    it 'counts each breach on the day it was recorded' do
      create(:support_ticket, account: account, first_response_breached_at: inside)
      create(:support_ticket, account: account, resolution_breached_at: inside)
      create(:support_ticket, account: account, resolution_breached_at: outside)

      expect(metrics.first_response_breaches).to eq(1)
      expect(metrics.resolution_breaches).to eq(1)
    end

    it "never counts another account's cases" do
      create(:support_ticket, account: other_account, created_at: inside)

      expect(metrics.tickets_created).to eq(0)
      expect(metrics.tickets_reopened).to eq(0)
    end
  end

  describe 'average_resolution_time' do
    it 'averages the cases resolved in the window, in seconds' do
      create(:support_ticket, account: account, created_at: inside - 2.hours, status: :resolved, resolved_at: inside)
      create(:support_ticket, account: account, created_at: inside - 4.hours, status: :resolved, resolved_at: inside)

      expect(metrics.average_resolution_time).to eq(3.hours.to_i)
    end

    # A zero would read as "we close instantly".
    it 'returns nil, not zero, when nothing was resolved' do
      create(:support_ticket, account: account, created_at: inside)

      expect(metrics.average_resolution_time).to be_nil
    end
  end

  describe 'current state' do
    it 'ignores the date range entirely' do
      create(:support_ticket, account: account, created_at: 2.years.ago, status: :open)
      create(:support_ticket, account: account, created_at: 2.years.ago, status: :resolved)
      create(:support_ticket, account: account, created_at: 2.years.ago, status: :open,
                              resolution_due_at: 1.hour.ago, assignee: agent)

      expect(metrics.open_now).to eq(2)
      expect(metrics.overdue_now).to eq(1)
      expect(metrics.unassigned_now).to eq(1)
    end
  end

  describe 'filters' do
    it 'narrows by inbox, team and assignee' do
      create(:support_ticket, account: account, created_at: inside, inbox: inbox, team: team, assignee: agent)
      create(:support_ticket, account: account, created_at: inside)

      expect(metrics(filters: { 'inbox_id' => inbox.id }).tickets_created).to eq(1)
      expect(metrics(filters: { 'team_id' => team.id }).tickets_created).to eq(1)
      expect(metrics(filters: { 'agent_id' => agent.id }).tickets_created).to eq(1)
    end

    it 'refuses a team from another account' do
      foreign = create(:team, account: other_account)

      expect { metrics(filters: { 'team_id' => foreign.id }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownFilterValue') })
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      create(:support_ticket, account: account, created_at: inside)

      points = metrics.series(:tickets_created)

      expect(points.length).to eq(7)
      expect(points.sum { |point| point[:value] }).to eq(1)
    end
  end

  describe 'breakdowns' do
    it 'groups by priority, category and status' do
      create(:support_ticket, account: account, created_at: inside, priority: :urgent, category: 'billing')
      create(:support_ticket, account: account, created_at: inside, priority: :urgent, category: 'technical')
      create(:support_ticket, account: account, created_at: inside, priority: :low, category: 'technical')

      expect(metrics.breakdown(:priority).first).to eq(id: 'urgent', label: 'urgent', value: 2)
      expect(metrics.breakdown(:category).first).to eq(id: 'technical', label: 'technical', value: 2)
      expect(metrics.breakdown(:status).sum { |row| row[:value] }).to eq(3)
    end

    it 'labels a team and an assignee by name, and skips the unassigned' do
      create(:support_ticket, account: account, created_at: inside, team: team, assignee: agent)
      create(:support_ticket, account: account, created_at: inside)

      expect(metrics.breakdown(:team)).to eq([{ id: team.id, label: team.name, value: 1 }])
      expect(metrics.breakdown(:assignee)).to eq([{ id: agent.id, label: agent.name, value: 1 }])
    end
  end
end
