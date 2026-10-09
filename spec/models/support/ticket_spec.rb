require 'rails_helper'

RSpec.describe Support::Ticket do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'reference numbering' do
    it 'numbers from one, per account, and renders the padded form' do
      first = create(:support_ticket, account: account)
      second = create(:support_ticket, account: account)
      elsewhere = create(:support_ticket, account: other_account)

      expect([first.reference_number, second.reference_number]).to eq([1, 2])
      expect(elsewhere.reference_number).to eq(1)
      expect(second.reference).to eq('TCK-000002')
    end

    it 'accepts either form when parsing a reference back' do
      expect(described_class.reference_number_from('TCK-000123')).to eq(123)
      expect(described_class.reference_number_from('123')).to eq(123)
      expect(described_class.reference_number_from('nonsense')).to be_nil
    end

    it 'refuses a duplicate number inside one account' do
      create(:support_ticket, account: account)
      duplicate = build(:support_ticket, account: account, reference_number: 1)

      expect(duplicate).not_to be_valid
    end
  end

  describe 'the three optional links' do
    # This is the whole reason the table exists: a Conversation requires an inbox
    # (db/schema.rb:1024, app/models/conversation.rb:77) and a contact (:78), and an internal operational case
    # has neither.
    it 'allows a case with no conversation, no contact and no inbox' do
      ticket = build(:support_ticket, account: account, category: 'operational')

      expect(ticket).to be_valid
      expect { ticket.save! }.not_to raise_error
    end
  end

  describe 'validations' do
    it 'requires a title' do
      expect(build(:support_ticket, account: account, title: nil)).not_to be_valid
    end

    it 'refuses a category outside the allow-list' do
      expect(build(:support_ticket, account: account, category: 'invented')).not_to be_valid
    end

    it 'refuses a source type outside the allow-list' do
      expect(build(:support_ticket, account: account, source_type: 'User', source_id: 1)).not_to be_valid
      expect(build(:support_ticket, account: account, source_type: 'Operations::Signal', source_id: 1)).to be_valid
    end

    it 'refuses a conversation from another account' do
      foreign = create(:conversation, account: other_account)
      ticket = build(:support_ticket, account: account, conversation: foreign)

      expect(ticket).not_to be_valid
      expect(ticket.errors[:conversation]).to include('must belong to the same account')
    end

    it 'refuses a contact, inbox, team or policy from another account' do
      expect(build(:support_ticket, account: account, contact: create(:contact, account: other_account))).not_to be_valid
      expect(build(:support_ticket, account: account, inbox: create(:inbox, account: other_account))).not_to be_valid
      expect(build(:support_ticket, account: account, team: create(:team, account: other_account))).not_to be_valid
      expect(build(:support_ticket, account: account,
                                    sla_policy: create(:support_sla_policy, account: other_account))).not_to be_valid
    end

    # A User is global in Chatwoot and joins an account through AccountUser, so membership is the check.
    it 'refuses an assignee who is not a member of the account' do
      outsider = create(:user, account: other_account, role: :agent)
      ticket = build(:support_ticket, account: account, assignee: outsider)

      expect(ticket).not_to be_valid
      expect(ticket.errors[:assignee]).to include('must be a member of the same account')
    end

    it 'accepts an assignee who is a member' do
      expect(build(:support_ticket, account: account, assignee: agent)).to be_valid
    end
  end

  describe 'scopes' do
    it 'separates active from terminal' do
      open_ticket = create(:support_ticket, account: account, status: :open)
      waiting = create(:support_ticket, account: account, status: :waiting_on_customer)
      resolved = create(:support_ticket, account: account, status: :resolved)

      expect(described_class.active).to contain_exactly(open_ticket, waiting)
      expect(described_class.terminal).to contain_exactly(resolved)
    end

    it 'counts a case overdue only while it is still active' do
      overdue = create(:support_ticket, account: account, status: :open, resolution_due_at: 1.hour.ago)
      create(:support_ticket, account: account, status: :resolved, resolution_due_at: 1.hour.ago)
      create(:support_ticket, account: account, status: :open, resolution_due_at: 1.hour.from_now)

      expect(described_class.overdue).to contain_exactly(overdue)
    end

    it 'treats either breach as breached' do
      first = create(:support_ticket, account: account, first_response_breached_at: 1.hour.ago)
      second = create(:support_ticket, account: account, resolution_breached_at: 1.hour.ago)
      create(:support_ticket, account: account)

      expect(described_class.breached).to contain_exactly(first, second)
    end
  end

  describe 'labels' do
    # Labelable is one macro and two methods (app/models/concerns/labelable.rb), so the account's existing
    # labels work on a case with no new code.
    it 'reuses the account label infrastructure' do
      ticket = create(:support_ticket, account: account)
      ticket.update_labels(%w[refund vip])

      expect(ticket.reload.label_list).to contain_exactly('refund', 'vip')
    end
  end
end
