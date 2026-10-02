require 'rails_helper'

# The Flow Builder API (docs/flow-builder/02-architecture.md): administrators of `lynomia_flow_builder` accounts, the
# account's own flow bots only, versioned drafts, and Test Mode that leaves nothing behind.
RSpec.describe 'Flows API', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/flows" }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:flow) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil, name: 'Welcome') }
  let(:node) { ->(id, type, data = {}) { { id: id, type: type, position: { x: 0, y: 0 }, data: data } } }
  let(:menu_graph) do
    { nodes: [node.call('start', 'start'),
              node.call('menu', 'buttons', text: 'How can we help?', options: [{ id: 'track', title: 'Track order' }, { id: 'care', title: 'Care' }]),
              node.call('track', 'send_message', text: 'Your order number?'), node.call('human', 'handoff', reason: 'Care asked'),
              node.call('end', 'end')],
      edges: [{ id: 'e1', source: 'start', sourceHandle: 'next', target: 'menu' },
              { id: 'e2', source: 'menu', sourceHandle: 'track', target: 'track' },
              { id: 'e3', source: 'menu', sourceHandle: 'care', target: 'human' },
              { id: 'e4', source: 'track', sourceHandle: 'next', target: 'end' }] }
  end

  it 'is for administrators of accounts with the Flow Builder, and only for their own flows' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    other = create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') }
    foreign = create(:agent_bot, account: other, bot_type: :flow, outgoing_url: nil)
    get "#{base}/#{foreign.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    account.disable_features!('lynomia_flow_builder')
    get base, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates a flow bot, saves its draft, refuses to publish an invalid one, and publishes a valid one' do
    post base, params: { name: 'Welcome', description: 'Main menu' }, headers: admin.create_new_auth_token, as: :json
    created = response.parsed_body
    expect(AgentBot.find(created['id'])).to have_attributes(bot_type: 'flow', account_id: account.id, outgoing_url: nil)
    expect(created['graph']['nodes'].pluck('type')).to eq(%w[start end])

    put "#{base}/#{created['id']}/draft", params: { graph: { nodes: 'x' } }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['errors'].pluck('code')).to eq(['invalid_graph'])

    broken = menu_graph.merge(edges: menu_graph[:edges].first(2))
    put "#{base}/#{created['id']}/draft", params: { graph: broken }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['errors'].pluck('code')).to include('unconnected_output')
    post "#{base}/#{created['id']}/publish", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    put "#{base}/#{created['id']}/draft", params: { graph: menu_graph }, headers: admin.create_new_auth_token, as: :json
    post "#{base}/#{created['id']}/publish", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['published']).to include('version' => 1, 'status' => 'published')
  end

  it 'deletes only a flow that is not published' do
    Flows::Versions.new(flow).tap { |versions| versions.save!(menu_graph.deep_stringify_keys) }.publish!

    delete "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['errors'].pluck('code')).to eq(['flow_active'])

    post "#{base}/#{flow.id}/disable", headers: admin.create_new_auth_token, as: :json
    delete "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
    expect(AgentBot.exists?(flow.id)).to be(false)
  end

  it 'tests the draft on the real runtime and keeps nothing: no message, conversation, contact or job' do
    AgentBotInbox.create!(inbox: whatsapp.inbox, agent_bot: flow)
    Flows::Versions.new(flow).save!(menu_graph.deep_stringify_keys)
    counts = -> { [Message.count, Conversation.count, Contact.count, FlowSession.count] }
    before = counts.call
    inputs = [{ text: 'hi' }, { text: 'Track order', reply_id: 'lfb:menu:track' }]

    headers = admin.create_new_auth_token

    expect { post "#{base}/#{flow.id}/simulate", params: { inputs: inputs }, headers: headers, as: :json }.not_to have_enqueued_job

    body = response.parsed_body
    expect(body['transcript'].map { |entry| [entry['from'], entry['text']] })
      .to eq([%w[customer hi], ['bot', 'How can we help?'], ['customer', 'Track order'], ['bot', 'Your order number?']])
    expect(body['transcript'][1]['items'].pluck('value')).to eq(%w[lfb:menu:track lfb:menu:care])
    expect(body['session']).to include('status' => 'completed')
    expect(body['trace'].pluck('event')).to include('flow.execution.started', 'flow.node.executed', 'flow.execution.completed')
    expect(counts.call).to eq(before)
  end

  it 'shows the latest sessions without what customers wrote' do
    AgentBotInbox.create!(inbox: whatsapp.inbox, agent_bot: flow)
    version = Flows::Versions.new(flow).tap { |versions| versions.save!(menu_graph.deep_stringify_keys) }.publish!
    conversation = create(:conversation, account: account, inbox: whatsapp.inbox)
    FlowSession.create!(account: account, agent_bot: flow, flow_version: version, conversation: conversation, status: :handed_off,
                        current_node_id: 'menu', context: { 'reply' => 'my secret address', 'end_reason' => 'no_choice' })

    get "#{base}/#{flow.id}/sessions", headers: admin.create_new_auth_token, as: :json

    entry = response.parsed_body['payload'].first
    expect(entry).to include('status' => 'handed_off', 'current_node_id' => 'menu', 'end_reason' => 'no_choice',
                             'conversation_id' => conversation.display_id, 'version' => 1)
    expect(response.body).not_to include('my secret address')
  end
end
