require 'rails_helper'

# Chatwoot audits a deleted conversation and nothing else about it. Lynomia keeps that declaration
# (custom/app/models/custom/audit/conversation.rb), included at the site Chatwoot already carries
# (app/models/conversation.rb:434), so this holds with or without the Enterprise overlay.
#
# The conversation is created with `let!` on purpose: building one also creates an audited account and
# inbox, so counting from inside the expectation block would count those rows too.
RSpec.describe 'Conversation Audit', type: :model do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account) }

  it 'includes the audit declaration through the site Chatwoot provides' do
    expect(Conversation.ancestors).to include(Custom::Audit::Conversation)
  end

  describe 'audit logging on destroy' do
    it 'creates an audit log when conversation is destroyed' do
      expect { conversation.destroy! }.to change(Audited::Audit, :count).by(1)

      expect(Custom::AuditLog.last).to have_attributes(auditable_type: 'Conversation', action: 'destroy', auditable_id: conversation.id)
    end

    it 'does not create audit log for other actions by default' do
      expect { conversation.update!(priority: 'high') }.not_to(change(Audited::Audit, :count))
    end
  end
end
