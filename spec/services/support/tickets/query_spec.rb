require 'rails_helper'

RSpec.describe Support::Tickets::Query do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }

  def query(params = {})
    described_class.new(account: account, scope: Support::Ticket.where(account_id: account.id),
                        user: agent, params: params).call
  end

  describe 'status' do
    it 'resolves the active and terminal groups the tabs are built from' do
      open_ticket = create(:support_ticket, account: account, status: :open)
      waiting = create(:support_ticket, account: account, status: :waiting_on_customer)
      resolved = create(:support_ticket, account: account, status: :resolved)

      expect(query(status: 'active')).to contain_exactly(open_ticket, waiting)
      expect(query(status: 'terminal')).to contain_exactly(resolved)
      expect(query(status: 'open')).to contain_exactly(open_ticket)
    end

    it 'accepts several statuses, comma separated or repeated' do
      open_ticket = create(:support_ticket, account: account, status: :open)
      resolved = create(:support_ticket, account: account, status: :resolved)
      create(:support_ticket, account: account, status: :closed)

      expect(query(status: 'open,resolved')).to contain_exactly(open_ticket, resolved)
      expect(query(status: %w[open resolved])).to contain_exactly(open_ticket, resolved)
    end

    it 'refuses an unknown status rather than returning an empty page' do
      expect { query(status: 'escalated') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnsupportedStatus') })
    end
  end

  describe 'ownership' do
    it 'resolves me and unassigned without the client knowing its own id or how to express a NULL' do
      mine = create(:support_ticket, account: account, assignee: agent)
      theirs = create(:support_ticket, account: account, assignee: other_agent)
      nobody = create(:support_ticket, account: account)

      expect(query(assignee_id: 'me')).to contain_exactly(mine)
      expect(query(assignee_id: 'unassigned')).to contain_exactly(nobody)
      expect(query(assignee_id: other_agent.id.to_s)).to contain_exactly(theirs)
    end

    it 'refuses an assignee who is not a member of the account' do
      outsider = create(:user, account: other_account, role: :agent)

      expect { query(assignee_id: outsider.id.to_s) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnknownFilterValue') })
    end

    it 'filters by team and refuses a foreign team' do
      ours = create(:support_ticket, account: account, team: team)
      create(:support_ticket, account: account)

      expect(query(team_id: team.id.to_s)).to contain_exactly(ours)
      expect { query(team_id: create(:team, account: other_account).id.to_s) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnknownFilterValue') })
    end
  end

  describe 'links' do
    it 'filters by contact, inbox and conversation, each validated against the account' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      linked = create(:support_ticket, account: account, contact: contact, inbox: inbox, conversation: conversation)
      create(:support_ticket, account: account)

      expect(query(contact_id: contact.id.to_s)).to contain_exactly(linked)
      expect(query(inbox_id: inbox.id.to_s)).to contain_exactly(linked)
      expect(query(conversation_id: conversation.id.to_s)).to contain_exactly(linked)
    end

    it 'refuses an id from another account for every link' do
      {
        contact_id: create(:contact, account: other_account),
        inbox_id: create(:inbox, account: other_account),
        conversation_id: create(:conversation, account: other_account)
      }.each do |filter, record|
        expect { query(filter => record.id.to_s) }
          .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnknownFilterValue') })
      end
    end

    it 'refuses a non-numeric id rather than coercing it' do
      expect { query(contact_id: 'all') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnknownFilterValue') })
    end
  end

  describe 'sla state' do
    it 'separates overdue, breached, governed and ungoverned' do
      policy = create(:support_sla_policy, account: account)
      overdue = create(:support_ticket, account: account, status: :open, sla_policy: policy,
                                        resolution_due_at: 1.hour.ago)
      breached = create(:support_ticket, account: account, sla_policy: policy, resolution_breached_at: 1.hour.ago)
      governed = create(:support_ticket, account: account, sla_policy: policy, resolution_due_at: 1.day.from_now)
      ungoverned = create(:support_ticket, account: account)

      expect(query(sla: 'overdue')).to contain_exactly(overdue)
      expect(query(sla: 'breached')).to contain_exactly(breached)
      expect(query(sla: 'met_or_pending')).to contain_exactly(overdue, governed)
      expect(query(sla: 'none')).to contain_exactly(ungoverned)
    end

    it 'refuses an unknown sla state' do
      expect { query(sla: 'nearly') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnknownFilterValue') })
    end
  end

  describe 'search' do
    it 'matches a reference in either form, and does not fall through to a title search' do
      target = create(:support_ticket, account: account, title: 'Totally unrelated')
      create(:support_ticket, account: account, title: 'TCK mentioned in the title')

      expect(query(q: target.reference)).to contain_exactly(target)
      expect(query(q: target.reference_number.to_s)).to contain_exactly(target)
    end

    it 'matches a title case-insensitively' do
      target = create(:support_ticket, account: account, title: 'Refund NOT received')
      create(:support_ticket, account: account, title: 'Something else')

      expect(query(q: 'refund not')).to contain_exactly(target)
    end

    it 'treats a wildcard in the term as a literal' do
      create(:support_ticket, account: account, title: 'plain')

      expect(query(q: '%')).to be_empty
    end
  end

  describe 'sort and page' do
    it 'defaults to most recent activity first' do
      older = create(:support_ticket, account: account, last_activity_at: 2.days.ago)
      newer = create(:support_ticket, account: account, last_activity_at: 1.hour.ago)

      expect(query.to_a).to eq([newer, older])
    end

    it 'refuses an unknown sort key' do
      expect { query(sort: 'title') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::UnsupportedSort') })
    end

    it 'pages, with an explicit bound' do
      3.times { |i| create(:support_ticket, account: account, last_activity_at: i.hours.ago) }

      page = query(per_page: '2')
      expect(page.length).to eq(2)
      expect(page.total_count).to eq(3)
      expect(query(per_page: '2', page: '2').length).to eq(1)
    end

    it 'refuses a page size outside the bound' do
      %w[0 101 all].each do |value|
        expect { query(per_page: value) }
          .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::InvalidLimit') })
      end
    end
  end

  describe 'tenant isolation' do
    # The query receives a policy-scoped relation, but it must not be able to widen it either.
    it "never returns another account's cases" do
      create(:support_ticket, account: other_account, title: 'Theirs')
      mine = create(:support_ticket, account: account, title: 'Mine')

      expect(query).to contain_exactly(mine)
      expect(query(q: 'Theirs')).to be_empty
    end
  end
end
