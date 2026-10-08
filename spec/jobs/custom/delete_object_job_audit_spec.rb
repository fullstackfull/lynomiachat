require 'rails_helper'

# The audit row for a deleted inbox or conversation. The OSS job calls `process_post_deletion_tasks` after the
# destroy and leaves the body empty; Custom::DeleteObjectJob is what fills it. Before that module existed every
# "writes one row" example here failed with `expected 1, got 0` -- and `inbox:destroy`, which the dashboard's
# activity map offers, could never be produced at all.
RSpec.describe DeleteObjectJob do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let(:ip) { '203.0.113.9' }

  it 'is owned by the Lynomia module, with no Enterprise module in the chain' do
    expect(described_class.instance_method(:process_post_deletion_tasks).owner.to_s).to eq('Custom::DeleteObjectJob')
    expect(described_class.ancestors.map(&:to_s).grep(/Enterprise/)).to be_empty
  end

  describe 'deleting an inbox' do
    let!(:inbox) { create(:inbox, account: account) }

    it 'writes exactly one Inbox destroy row' do
      expect { described_class.perform_now(inbox, user, ip) }
        .to change(Custom::AuditLog.where(auditable_type: 'Inbox', action: 'destroy'), :count).by(1)
    end

    it 'attributes the row to the acting user, the account and the request address' do
      inbox_id = inbox.id
      described_class.perform_now(inbox, user, ip)

      audit = Custom::AuditLog.where(auditable_type: 'Inbox', action: 'destroy').last
      expect(audit.auditable_id).to eq(inbox_id)
      expect(audit.user_id).to eq(user.id)
      expect(audit.associated_type).to eq('Account')
      expect(audit.associated_id).to eq(account.id)
      expect(audit.remote_address).to eq(ip)
    end

    it 'records the destroyed attributes, which is what the original did' do
      name = inbox.name
      described_class.perform_now(inbox, user, ip)

      expect(Custom::AuditLog.where(auditable_type: 'Inbox', action: 'destroy').last.audited_changes['name']).to eq(name)
    end

    it 'writes nothing when no user is supplied, as in a Super Admin account deletion' do
      expect { described_class.perform_now(inbox, nil, nil) }.not_to change(Custom::AuditLog, :count)
    end
  end

  describe 'deleting a conversation' do
    let!(:conversation) { create(:conversation, account: account) }

    # Custom::Audit::Conversation is `audited only: [], on: [:destroy]`, so the declaration writes its own row on
    # destroy and this job writes a second one carrying the attributes. That is the pre-removal behaviour, asserted
    # here so a future change to either writer is visible rather than silent.
    it 'writes the job row in addition to the row the audited declaration writes' do
      expect { described_class.perform_now(conversation, user, ip) }
        .to change(Custom::AuditLog.where(auditable_type: 'Conversation', action: 'destroy'), :count).by(2)
    end

    it 'records the display_id the dashboard reads to name the conversation' do
      display_id = conversation.display_id
      described_class.perform_now(conversation, user, ip)

      rows = Custom::AuditLog.where(auditable_type: 'Conversation', action: 'destroy')
      expect(rows.map { |row| row.audited_changes['display_id'] }).to include(display_id)
    end
  end

  it 'writes nothing for an object type the original did not audit' do
    contact = create(:contact, account: account)
    contact.reload

    expect { described_class.perform_now(contact, user, ip) }.not_to change(Custom::AuditLog, :count)
  end
end
