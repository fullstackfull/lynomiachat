require 'rails_helper'

# Lynomia owns the audit class (docs/enterprise-audit/02-zero-dependency-implementation.md). These examples pin the
# two things that would otherwise regress silently once Chatwoot's Enterprise overlay goes: that the active class is
# Lynomia's, on the same `audits` table and still filling `username`, and that each mirrored Chatwoot-side
# declaration writes exactly one row -- not zero, and not two while both overlays are loaded.
RSpec.describe Custom::AuditLog do
  let(:account) { create(:account) }
  # `let!` so the membership this creates is audited before an example starts counting rows.
  let!(:user) { create(:user, account: account, role: :administrator) }

  it 'is the class the audited gem writes through, on the OSS audits table' do
    expect(Audited.audit_class).to eq(described_class)
    expect(described_class.table_name).to eq('audits')
    expect(described_class.superclass).to eq(Audited::Audit)
  end

  it 'records the acting user on a Lynomia flow event' do
    agent_bot = create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil)

    expect { Flows::Audit.record('flow.published', agent_bot, user: user, changes: { 'published' => true }) }
      .to change(described_class, :count).by(1)

    expect(described_class.last).to have_attributes(auditable: agent_bot, associated: account, user: user,
                                                    action: 'update', comment: 'flow.published', username: user.email)
  end

  # The account is an auditable in its own right for the events that happen before a store exists
  # (Commerce::AuditTrail's header names commerce.salla.connect_started), which keeps this example off
  # Commerce::Store's encrypted credentials.
  it 'records a Lynomia Commerce event against the account it happened to' do
    expect { Commerce::AuditTrail.record('commerce.salla.connect_started', auditable: account, user: user) }
      .to change(described_class, :count).by(1)

    expect(described_class.last).to have_attributes(auditable: account, associated: account, action: 'update',
                                                    comment: 'commerce.salla.connect_started', username: user.email)
  end

  it 'audits a shared contact audience but not a conversation folder' do
    audience = nil
    expect { audience = create(:custom_filter, account: account, user: user, filter_type: :contact) }
      .to change { described_class.where(auditable_type: 'CustomFilter').count }.by(1)
    expect(described_class.where(auditable: audience).last).to have_attributes(action: 'create', associated: account)

    expect { create(:custom_filter, account: account, user: user, filter_type: :conversation) }
      .not_to(change { described_class.where(auditable_type: 'CustomFilter').count })
  end

  describe 'the mirrored Chatwoot-side declarations' do
    let!(:inbox) { create(:inbox, account: account) }

    it 'writes exactly one row for an inbox update' do
      expect { inbox.update!(name: 'Renamed') }.to change { described_class.where(auditable: inbox, action: 'update').count }.by(1)
    end

    it 'writes exactly one row each for an inbox member added and removed' do
      member = nil
      expect { member = create(:inbox_member, inbox: inbox, user: user) }
        .to change { described_class.where(auditable_type: 'InboxMember', action: 'create').count }.by(1)
      expect { member.destroy! }
        .to change { described_class.where(auditable_type: 'InboxMember', action: 'destroy').count }.by(1)
    end

    it 'writes exactly one row each for a team member added and removed' do
      team = create(:team, account: account)
      member = nil
      expect { member = create(:team_member, team: team, user: user) }
        .to change { described_class.where(auditable_type: 'TeamMember', action: 'create').count }.by(1)
      expect { member.destroy! }
        .to change { described_class.where(auditable_type: 'TeamMember', action: 'destroy').count }.by(1)
    end

    it 'writes exactly one row for a macro, a webhook, an automation rule and an agent bot' do
      {
        'Macro' => -> { create(:macro, account: account, created_by: user, updated_by: user) },
        'Webhook' => -> { create(:webhook, account: account, inbox: inbox) },
        'AutomationRule' => -> { create(:automation_rule, account: account) },
        'AgentBot' => -> { create(:agent_bot, account: account) }
      }.each do |auditable_type, build|
        record = nil
        expect { record = build.call }.to change { described_class.where(auditable_type: auditable_type, action: 'create').count }.by(1)
        expect(described_class.where(auditable: record, action: 'create').count).to eq(1)
      end
    end

    it 'keeps a webhook secret and an agent bot secret out of the recorded changes' do
      webhook = create(:webhook, account: account, inbox: inbox)
      agent_bot = create(:agent_bot, account: account)

      expect(described_class.where(auditable: webhook).last.audited_changes.keys).not_to include('secret')
      expect(described_class.where(auditable: agent_bot).last.audited_changes.keys).not_to include('secret')
    end
  end
end
