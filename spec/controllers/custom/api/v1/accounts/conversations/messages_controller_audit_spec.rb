require 'rails_helper'

# The audit row for a deleted message. The OSS controller owns the deletion and declares the `prepend_mod_with`;
# Custom::Api::V1::Accounts::Conversations::MessagesController is what writes the row. Before that module existed
# every "writes one row" example here failed with `expected 1, got 0` while the deletion examples passed, which is
# exactly the shape of the gap: the product worked, the audit trail did not.
#
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Message deletion audit', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:message) { create(:message, account: account, content: 'the original body') }
  let(:conversation) { message.conversation }

  before { create(:inbox_member, inbox: conversation.inbox, user: agent) }

  def delete_message(id: message.id, headers: agent.create_new_auth_token)
    delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{id}",
           headers: headers, as: :json
  end

  it 'is owned by the Lynomia module, with no Enterprise module in the chain' do
    controller = Api::V1::Accounts::Conversations::MessagesController

    expect(controller.instance_method(:destroy).owner.to_s)
      .to eq('Custom::Api::V1::Accounts::Conversations::MessagesController')
    expect(controller.ancestors.map(&:to_s).grep(/Enterprise/)).to be_empty
  end

  it 'writes exactly one destroy row for an authorized delete' do
    expect { delete_message }.to change(Custom::AuditLog.where(auditable_type: 'Message'), :count).by(1)

    expect(response).to have_http_status(:success)
  end

  it 'records the message, the actor, the account and the snapshot taken before the delete' do
    delete_message

    audit = Custom::AuditLog.where(auditable_type: 'Message').last
    expect(audit.auditable_id).to eq(message.id)
    expect(audit.action).to eq('destroy')
    expect(audit.user_id).to eq(agent.id)
    expect(audit.user_type).to eq('User')
    expect(audit.username).to eq(agent.email)
    expect(audit.associated_type).to eq('Account')
    expect(audit.associated_id).to eq(account.id)
    expect(audit.remote_address).to be_present
  end

  # These six keys are a contract, not a choice: the serializer drops `content` when rendering and the dashboard
  # reads `display_id` to name the conversation in the activity line.
  it 'snapshots the pre-delete content and the conversation, inbox and sender identifiers' do
    delete_message

    expect(Custom::AuditLog.where(auditable_type: 'Message').last.audited_changes).to eq(
      'content' => 'the original body',
      'conversation_id' => conversation.id,
      'display_id' => conversation.display_id,
      'inbox_id' => message.inbox_id,
      'sender_type' => message.sender_type,
      'sender_id' => message.sender_id
    )
  end

  it 'still soft-deletes the message exactly as the OSS controller did' do
    attachment_message = create(:message, account: account, conversation: conversation, content: 'with a file')
    attachment_message.attachments.create!(account_id: account.id, file_type: :image, external_url: 'https://example.com/a.png')

    delete_message(id: attachment_message.id)

    expect(response).to have_http_status(:success)
    expect(attachment_message.reload.content).to eq('This message was deleted')
    expect(attachment_message.reload.deleted).to be true
    expect(attachment_message.reload.attachments).to be_empty
  end

  it 'writes no second row when an already-deleted message is deleted again' do
    delete_message
    expect(Custom::AuditLog.where(auditable_type: 'Message').count).to eq(1)

    expect { delete_message }.not_to change(Custom::AuditLog.where(auditable_type: 'Message'), :count)
    expect(response).to have_http_status(:success)
  end

  it 'leaves an unauthenticated delete refused and unaudited' do
    expect { delete_message(headers: nil) }.not_to change(Custom::AuditLog, :count)

    expect(response).to have_http_status(:unauthorized)
    expect(message.reload.deleted).to be_falsey
  end

  it 'leaves a delete by an agent of another account refused and unaudited' do
    outsider = create(:user, account: create(:account), role: :agent)

    expect { delete_message(headers: outsider.create_new_auth_token) }.not_to change(Custom::AuditLog, :count)

    expect(response).to have_http_status(:not_found).or have_http_status(:unauthorized)
    expect(message.reload.deleted).to be_falsey
  end

  # Reader compatibility, proven through the real endpoint rather than asserted. Both new row types have to come
  # back under the event-type filters the dashboard already offers.
  describe 'the audit log reader' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }

    before do
      account.enable_features!('audit_logs')
      delete_message
      channel.update!(phone_number: '+19998887777')
    end

    it 'returns the message deletion row under the Message filter, without the deleted body' do
      get "/api/v1/accounts/#{account.id}/audit_logs", params: { types: ['Message'] },
                                                       headers: administrator.create_new_auth_token, as: :json

      row = response.parsed_body['audit_logs'].find { |log| log['auditable_type'] == 'Message' }
      expect(row['action']).to eq('destroy')
      expect(row['audited_changes']).not_to have_key('content')
      expect(row['audited_changes']['display_id']).to eq(conversation.display_id)
    end

    it 'returns the channel configuration row under the Inbox filter, with the credential filtered' do
      channel.update!(business_management_token: 'EAAG-live-token')

      get "/api/v1/accounts/#{account.id}/audit_logs", params: { types: ['Inbox'] },
                                                       headers: administrator.create_new_auth_token, as: :json

      # The Inbox family also carries the `create` rows from Custom::Audit::Inbox, so the update rows are selected
      # rather than assumed to be the only ones.
      updates = response.parsed_body['audit_logs']
                        .select { |log| log['auditable_type'] == 'Inbox' && log['action'] == 'update' }
      expect(updates).not_to be_empty
      expect(updates.flat_map { |row| row['audited_changes'].keys }).to include('business_management_token')
      expect(response.body).not_to include('EAAG-live-token')
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
