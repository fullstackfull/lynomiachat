require 'rails_helper'

# Package B: what Lynomia records when somebody changes something
# (docs/p-final/clean-room/specs/B-audit-event-capture.md, acceptance plan section B).
#
# Every scenario is asserted through package A's read surface -- a GET of the account's trail as an
# administrator -- because that is the record's only reader, and a capture point whose row the trail cannot
# return has recorded nothing an operator can use. Two assertions go further and read the stored row as well:
# a deleted message's body and a channel's credential have to be absent from the table itself, since a value
# withheld only on the way out is still a value in the database (package B §5).
RSpec.describe 'Audit event capture', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # The trail is capability-gated (package A §2). Without this every assertion below would pass against an
  # empty page for the wrong reason.
  before { account.enable_features!('audit_logs') }

  def as(user, verb, path, params = {})
    public_send(verb, "/api/v1/accounts/#{account.id}#{path}", params: params, headers: user.create_new_auth_token, as: :json)
  end

  # Package A's read surface, called the way the settings page calls it. Returns the entries so an example can
  # look for its own; `response` is left holding the trail's own body, which the credential scenarios search.
  def trail(reader = admin, tenant = account)
    get "/api/v1/accounts/#{tenant.id}/audit_logs", headers: reader.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['audit_logs']
  end

  describe 'B-1 an account settings change' do
    it 'names the account, the actor, the changed field and the value before and after' do
      previous_name = account.name

      as(admin, :patch, '', { name: 'Premier Care Kuwait' })
      expect(response).to have_http_status(:success)

      entry = trail.find { |entry| entry['auditable_type'] == 'Account' }
      expect(entry).to include('action' => 'update', 'auditable_id' => account.id, 'user_id' => admin.id,
                               'username' => admin.available_name)
      expect(entry['audited_changes']).to eq('name' => [previous_name, 'Premier Care Kuwait'])
    end
  end

  describe 'B-2 a role change' do
    it 'carries who was changed, by whom, and both roles' do
      as(admin, :patch, "/agents/#{agent.id}", { agent: { role: 'administrator' } })
      expect(response).to have_http_status(:success)

      entry = trail.find { |entry| entry['auditable_type'] == 'AccountUser' && entry['action'] == 'update' }
      expect(entry).to include('user_id' => admin.id, 'username' => admin.available_name)
      # The roles are the enum's stored values, which is what the browser's label reads out of the change pair.
      expect(entry['audited_changes']).to eq('role' => [AccountUser.roles['agent'], AccountUser.roles['administrator']])
      expect(entry['auditable']).to eq('user_id' => agent.id)
    end
  end

  describe "B-3 editing your own membership versus somebody else's" do
    it 'produces two entries a reader can tell apart' do
      post '/api/v1/profile/availability', params: { profile: { account_id: account.id, availability: 'busy' } },
                                           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      as(admin, :patch, "/agents/#{agent.id}", { agent: { availability: 'busy' } })
      expect(response).to have_http_status(:success)

      # Self and other are told apart by comparing the entry's actor with the audited membership's own user,
      # which is the one fact about the auditable that package A discloses for exactly this purpose.
      edits = trail.select { |entry| entry['auditable_type'] == 'AccountUser' && entry['action'] == 'update' }
      own, others = edits.partition { |entry| entry['user_id'] == entry.dig('auditable', 'user_id') }
      expect(own.map { |entry| entry['user_id'] }).to eq([admin.id])
      expect(others.map { |entry| [entry['user_id'], entry.dig('auditable', 'user_id')] }).to eq([[admin.id, agent.id]])
    end
  end

  describe 'B-4 a membership change whose user is then deleted' do
    it 'is still returned and still attributable' do
      as(admin, :patch, "/agents/#{agent.id}", { agent: { role: 'administrator' } })

      perform_enqueued_jobs { as(admin, :delete, "/agents/#{agent.id}") }
      expect(User.exists?(agent.id)).to be(false)

      entry = trail.find { |entry| entry['auditable_type'] == 'AccountUser' && entry['action'] == 'update' }
      # The name was captured when the row was written, so the entry survives its subject and stays readable.
      expect(entry).to include('user_id' => admin.id, 'username' => admin.available_name)
      expect(entry['audited_changes']).to eq('role' => [AccountUser.roles['agent'], AccountUser.roles['administrator']])
      # The membership went with the user; a null auditable is the signal the browser renders for that.
      expect(entry['auditable']).to be_nil
    end
  end

  describe 'B-5 inbox lifecycle' do
    it 'records three distinguishable actions, all naming the inbox' do
      as(admin, :post, '/inboxes', { name: 'Front desk', channel: { type: 'api', webhook_url: '' } })
      expect(response).to have_http_status(:success)
      inbox_id = response.parsed_body['id']

      as(admin, :patch, "/inboxes/#{inbox_id}", { name: 'Front desk (KW)' })
      perform_enqueued_jobs { as(admin, :delete, "/inboxes/#{inbox_id}") }

      entries = trail.select { |entry| entry['auditable_type'] == 'Inbox' }
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('create', 'update', 'destroy')
      expect(entries.map { |entry| entry['auditable_id'] }.uniq).to eq([inbox_id])
      expect(entries.find { |entry| entry['action'] == 'update' }['audited_changes'])
        .to eq('name' => ['Front desk', 'Front desk (KW)'])
    end
  end

  describe 'B-6 inbox membership' do
    let(:inbox) { create(:inbox, account: account) }

    it 'records the addition and the removal, naming the member and the inbox' do
      as(admin, :post, '/inbox_members', { inbox_id: inbox.id, user_ids: [agent.id] })
      expect(response).to have_http_status(:success)

      as(admin, :delete, '/inbox_members', { inbox_id: inbox.id, user_ids: [agent.id] })
      expect(response).to have_http_status(:success)

      entries = trail.select { |entry| entry['auditable_type'] == 'InboxMember' }
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('create', 'destroy')
      expect(entries.map { |entry| entry['audited_changes'].values_at('user_id', 'inbox_id') }.uniq)
        .to eq([[agent.id, inbox.id]])
    end
  end

  describe 'B-7 team lifecycle and team membership' do
    it 'records four entries, each naming its subject' do
      as(admin, :post, '/teams', { team: { name: 'Billing' } })
      team_id = response.parsed_body['id']

      as(admin, :post, "/teams/#{team_id}/team_members", { user_ids: [agent.id] })
      as(admin, :delete, "/teams/#{team_id}/team_members", { user_ids: [agent.id] })
      as(admin, :delete, "/teams/#{team_id}")
      expect(response).to have_http_status(:success)

      team_types = %w[Team TeamMember]
      entries = trail.select { |entry| team_types.include?(entry['auditable_type']) }
      expect(entries.map { |entry| [entry['auditable_type'], entry['action']] })
        .to contain_exactly(%w[Team create], %w[TeamMember create], %w[TeamMember destroy], %w[Team destroy])
      expect(entries.select { |entry| entry['auditable_type'] == 'TeamMember' }
                    .map { |entry| entry['audited_changes'].values_at('user_id', 'team_id') }.uniq)
        .to eq([[agent.id, team_id]])
    end
  end

  describe 'B-8 automation rule lifecycle' do
    it 'records three entries naming the rule' do
      as(admin, :post, '/automation_rules',
         { name: 'Close resolved', event_name: 'conversation_updated',
           conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['resolved'], query_operator: nil }],
           actions: [{ action_name: 'add_label', action_params: ['support'] }] })
      expect(response).to have_http_status(:success)
      rule_id = response.parsed_body['id']

      as(admin, :patch, "/automation_rules/#{rule_id}", { name: 'Close resolved (KW)' })
      as(admin, :delete, "/automation_rules/#{rule_id}")

      entries = trail.select { |entry| entry['auditable_type'] == 'AutomationRule' }
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('create', 'update', 'destroy')
      expect(entries.map { |entry| entry['auditable_id'] }.uniq).to eq([rule_id])
      expect(entries.find { |entry| entry['action'] == 'update' }['audited_changes'])
        .to eq('name' => ['Close resolved', 'Close resolved (KW)'])
    end
  end

  describe 'B-9 macro lifecycle' do
    it 'records three entries naming the macro' do
      as(admin, :post, '/macros', { name: 'Greet', visibility: 'global',
                                    actions: [{ action_name: 'add_label', action_params: ['hi'] }] })
      expect(response).to have_http_status(:success)
      macro_id = response.parsed_body['payload']['id']

      as(admin, :patch, "/macros/#{macro_id}", { name: 'Greet (KW)', visibility: 'global' })
      as(admin, :delete, "/macros/#{macro_id}")

      entries = trail.select { |entry| entry['auditable_type'] == 'Macro' }
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('create', 'update', 'destroy')
      expect(entries.map { |entry| entry['auditable_id'] }.uniq).to eq([macro_id])
      expect(entries.find { |entry| entry['action'] == 'update' }['audited_changes'])
        .to eq('name' => ['Greet', 'Greet (KW)'])
    end
  end

  describe 'B-10 webhook lifecycle' do
    it 'records three entries naming the webhook' do
      as(admin, :post, '/webhooks', { webhook: { url: 'https://hook.test/orders', subscriptions: ['conversation_created'] } })
      expect(response).to have_http_status(:success)
      webhook_id = response.parsed_body['payload']['webhook']['id']

      as(admin, :patch, "/webhooks/#{webhook_id}", { webhook: { url: 'https://hook.test/orders-v2' } })
      as(admin, :delete, "/webhooks/#{webhook_id}")

      entries = trail.select { |entry| entry['auditable_type'] == 'Webhook' }
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('create', 'update', 'destroy')
      expect(entries.map { |entry| entry['auditable_id'] }.uniq).to eq([webhook_id])
      expect(entries.find { |entry| entry['action'] == 'update' }['audited_changes'])
        .to eq('url' => ['https://hook.test/orders', 'https://hook.test/orders-v2'])
      # The signing secret Lynomia proves its deliveries with is never part of the record.
      expect(entries.flat_map { |entry| entry['audited_changes'].keys }).not_to include('secret')
    end
  end

  describe 'B-11 agent bot lifecycle' do
    it 'records three entries naming the bot' do
      as(admin, :post, '/agent_bots', { name: 'Greeter', description: 'says hi', outgoing_url: 'https://bot.test/hook' })
      expect(response).to have_http_status(:success)
      bot_id = response.parsed_body['id']

      as(admin, :patch, "/agent_bots/#{bot_id}", { name: 'Greeter (KW)' })
      as(admin, :delete, "/agent_bots/#{bot_id}")

      entries = trail.select { |entry| entry['auditable_type'] == 'AgentBot' }
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('create', 'update', 'destroy')
      expect(entries.map { |entry| entry['auditable_id'] }.uniq).to eq([bot_id])
      expect(entries.find { |entry| entry['action'] == 'update' }['audited_changes'])
        .to eq('name' => ['Greeter', 'Greeter (KW)'])
    end
  end

  describe 'B-12 a deleted conversation' do
    it 'is named by the number the product shows, not only by its internal id' do
      conversation = create(:conversation, account: account, inbox: create(:inbox, account: account))
      admin # created outside the block, so its own avatar job is not one of the jobs performed inside it

      perform_enqueued_jobs { as(admin, :delete, "/conversations/#{conversation.display_id}") }
      expect(response).to have_http_status(:success)

      entry = trail.find { |entry| entry['auditable_type'] == 'Conversation' }
      expect(entry).to include('action' => 'destroy', 'user_id' => admin.id)
      # display_id is the number on the conversation in the product; the internal id is also there but is not
      # what a person recognises.
      expect(entry['audited_changes']['display_id']).to eq(conversation.display_id)
    end
  end

  describe 'message deletion' do
    let(:phrase) { 'pineapple-on-pizza-7781' }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: phrase) }
    let(:attachment) do
      record = message.attachments.new(account_id: account.id, file_type: :image)
      record.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'kuwait-id-scan-4412.png',
                         content_type: 'image/png')
      record.save!
      record
    end

    it 'B-13 names the conversation and keeps out the body and the attachment' do
      blob_key = attachment.file.blob.key

      as(admin, :delete, "/conversations/#{conversation.display_id}/messages/#{message.id}")
      expect(response).to have_http_status(:success)

      entry = trail.find { |entry| entry['auditable_type'] == 'Message' }
      expect(entry).to include('action' => 'destroy', 'comment' => 'message.deleted', 'auditable_id' => message.id)
      expect(entry['audited_changes']).to include('display_id' => conversation.display_id, 'inbox_id' => inbox.id)
      expect(response.body).not_to include(phrase, 'kuwait-id-scan-4412.png', blob_key)
      # Package B §5 is stricter than withholding on the way out: the content never reaches the table, so the
      # read surface needs no special case for this one record type.
      expect(Custom::AuditLog.pluck(:audited_changes, :comment).to_s).not_to include(phrase, 'kuwait-id-scan-4412.png', blob_key)
    end

    it 'B-14 records one entry for two deletions of the same message' do
      as(admin, :delete, "/conversations/#{conversation.display_id}/messages/#{message.id}")
      expect(response).to have_http_status(:success)
      after_first = trail.length

      as(admin, :delete, "/conversations/#{conversation.display_id}/messages/#{message.id}")
      expect(response).to have_http_status(:success)

      # The second deletion is a no-op the product already allows; what must not happen is a second row for the
      # one event, so the second call has to write nothing at all.
      expect(trail.length).to eq(after_first)
      expect(trail.count { |entry| entry['auditable_type'] == 'Message' }).to eq(1)
    end
  end

  describe 'B-15 sign-in and sign-out' do
    it 'records two entries for the member, each naming the account the session was for' do
      post '/auth/sign_in', params: { email: admin.email, password: 'Password1!' }, as: :json
      expect(response).to have_http_status(:success)

      delete '/auth/sign_out', headers: %w[access-token client uid token-type expiry].index_with { |key| response.headers[key] },
                               as: :json
      expect(response).to have_http_status(:success)

      entries = trail.select { |entry| entry['auditable_type'] == 'User' }
      # A verb rather than one of create/update/destroy, because a session is not a change to any row and
      # `user:sign_in` / `user:sign_out` are the labels the browser has for these two events.
      expect(entries.map { |entry| entry['action'] }).to contain_exactly('sign_in', 'sign_out')
      expect(entries.map { |entry| entry['comment'] }).to contain_exactly('user.sign_in', 'user.sign_out')
      expect(entries.map { |entry| entry['user_id'] }.uniq).to eq([admin.id])
      expect(entries.map { |entry| entry['audited_changes'] }.uniq).to eq([{ 'account_id' => account.id }])
    end
  end

  describe 'B-16 a failed sign-in' do
    it 'writes no success entry' do
      post '/auth/sign_in', params: { email: admin.email, password: 'not-the-password' }, as: :json
      expect(response).to have_http_status(:unauthorized)

      expect(trail.select { |entry| entry['auditable_type'] == 'User' }).to be_empty
    end
  end

  describe 'channel configuration' do
    let(:access_token) { 'EAAG-secret-whatsapp-access-token' }
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false)
        .tap { |whatsapp| whatsapp.update!(provider_config: whatsapp.provider_config.merge('api_key' => access_token)) }
    end

    before do
      stub_request(:get, %r{graph\.facebook\.com/v\d+\.\d+/\d+/message_templates})
        .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{graph\.facebook\.com/v\d+\.\d+/\d+/phone_numbers})
        .to_return(status: 200, body: { data: [{ id: '123456789' }, { id: '555000111' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    # What the dashboard holds and sends back. It never receives the credentials, so editing from it leaves
    # them alone -- which is what makes "the credential did not change" a real precondition for B-17.
    def browser_config
      as(admin, :get, "/inboxes/#{channel.inbox.id}")
      response.parsed_body['provider_config']
    end

    it 'B-17 records the changed field and never the credential' do
      config = browser_config

      as(admin, :patch, "/inboxes/#{channel.inbox.id}", { channel: { provider_config: config.merge('phone_number_id' => '555000111') } })
      expect(response).to have_http_status(:success)

      entry = trail.find { |entry| entry['comment'] == 'channel.configuration_changed' }
      # Recorded against the inbox: that is the labelled event, and it is the true one -- what the operator
      # edited was the inbox's channel configuration.
      expect(entry).to include('auditable_type' => 'Inbox', 'auditable_id' => channel.inbox.id, 'action' => 'update')
      expect(entry['audited_changes']['provider_config']).to eq('phone_number_id' => %w[123456789 555000111])
      expect(response.body).not_to include(access_token)
      expect(Custom::AuditLog.pluck(:audited_changes).to_s).not_to include(access_token)
    end

    it 'B-18 records a credential rotation without disclosing either value' do
      config = browser_config

      as(admin, :patch, "/inboxes/#{channel.inbox.id}", { channel: { provider_config: config.merge('api_key' => 'EAAG-rotated-token') } })
      expect(response).to have_http_status(:success)
      expect(channel.reload.provider_config['api_key']).to eq('EAAG-rotated-token')

      entry = trail.find { |entry| entry['comment'] == 'channel.credentials_changed' }
      # The names of the keys that moved, and nothing else: a masked value still discloses a secret's length
      # and a hash of one is still its fingerprint, so the field is omitted rather than transformed.
      expect(entry['audited_changes']).to eq('rotated_fields' => ['api_key'])
      expect(response.body).not_to include(access_token, 'EAAG-rotated-token')
      expect(Custom::AuditLog.pluck(:audited_changes).to_s).not_to include(access_token, 'EAAG-rotated-token')
    end
  end

  describe 'B-19 asynchronous deletion' do
    it 'names the administrator who asked for it, not the worker that performed it' do
      account.enable_features!('audit_log_ip_address')
      inbox = create(:inbox, account: account)
      create_list(:conversation, 2, account: account, inbox: inbox)

      DeleteObjectJob.perform_now(inbox, admin, '203.0.113.9')

      entries = trail
      entry = entries.find { |entry| entry['auditable_type'] == 'Inbox' && entry['action'] == 'destroy' }
      expect(entry).to include('user_id' => admin.id, 'user_type' => 'User', 'username' => admin.available_name)
      # The address of the request that asked for the deletion, carried into the job rather than the worker's.
      expect(entry['remote_address']).to eq('203.0.113.9')
      # One operator action, one entry: the deletion's fan-out through the inbox's conversations is not a set
      # of events, and a row per conversation would make recording cost grow with the record's associations.
      expect(entries.map { |row| row['auditable_type'] }).not_to include('Conversation')
    end
  end

  describe 'B-20 every entry carries an account' do
    let(:other_account) { create(:account) }
    let(:other_admin) { create(:user, account: other_account, role: :administrator) }

    # The same battery in two tenants, so a missing account predicate shows up as a doubled trail rather than
    # as nothing at all.
    def battery(tenant, tenant_admin)
      headers = tenant_admin.create_new_auth_token
      patch "/api/v1/accounts/#{tenant.id}", params: { name: "Renamed #{tenant.id}" }, headers: headers, as: :json
      post "/api/v1/accounts/#{tenant.id}/teams", params: { team: { name: "Team #{tenant.id}" } }, headers: headers, as: :json
      post "/api/v1/accounts/#{tenant.id}/webhooks", headers: headers, as: :json,
                                                     params: { webhook: { url: "https://hook.test/#{tenant.id}",
                                                                          subscriptions: ['conversation_created'] } }
    end

    it 'puts every produced event in exactly one trail and leaves none out of both' do
      other_account.enable_features!('audit_logs')
      battery(account, admin)
      battery(other_account, other_admin)

      mine = trail(admin, account)
      theirs = trail(other_admin, other_account)
      signatures = [%w[AccountUser create], %w[Account update], %w[Team create], %w[Webhook create]]

      expect(mine.map { |entry| [entry['auditable_type'], entry['action']] }).to match_array(signatures)
      expect(theirs.map { |entry| [entry['auditable_type'], entry['action']] }).to match_array(signatures)
      expect(mine.map { |entry| entry['id'] } & theirs.map { |entry| entry['id'] }).to be_empty
    end
  end

  describe 'B-21 a recording failure' do
    it 'leaves the product action successful and reports itself to operators' do
      admin # created before the store is broken, so the actor the entry would have named already exists
      allow(Rails.logger).to receive(:error)
      allow(Custom::AuditLog).to receive(:new).and_raise(ActiveRecord::StatementInvalid.new('relation "audits" does not exist'))

      as(admin, :patch, '', { name: 'Still renamed' })

      expect(response).to have_http_status(:success)
      expect(account.reload.name).to eq('Still renamed')
      # The end user is told nothing about auditing; operators are told everything.
      expect(response.body).not_to include('Lynomia::Audit')
      expect(Rails.logger).to have_received(:error).with(/\[Lynomia::Audit\]/)
    end
  end

  describe 'B-22 a machine credential' do
    let(:platform_app) { create(:platform_app) }

    before { create(:platform_app_permissible, platform_app: platform_app, permissible: account) }

    it 'has its account change recorded, and reading the entry does not raise' do
      previous_name = account.name

      patch "/platform/api/v1/accounts/#{account.id}", params: { name: 'Renamed by the integration' },
                                                       headers: { api_access_token: platform_app.access_token.token }, as: :json
      expect(response).to have_http_status(:success)

      entry = trail.find { |entry| entry['auditable_type'] == 'Account' }
      expect(entry['audited_changes']).to eq('name' => [previous_name, 'Renamed by the integration'])
      # No person did this, and the entry must not say one did -- whether it names the credential or nobody.
      expect(entry['user_type']).not_to eq('User')
    end

    it 'is named by the entry when it is the acting actor on a deletion' do
      inbox = create(:inbox, account: account)

      DeleteObjectJob.perform_now(inbox, platform_app, '198.51.100.7')

      entry = trail.find { |entry| entry['auditable_type'] == 'Inbox' && entry['action'] == 'destroy' }
      # The actor column is polymorphic and the display name is captured at write time for either kind of
      # actor, so a credential that is not a User at all is still named and still readable.
      expect(entry).to include('user_id' => platform_app.id, 'user_type' => 'PlatformApp', 'username' => platform_app.name)
    end
  end
end
