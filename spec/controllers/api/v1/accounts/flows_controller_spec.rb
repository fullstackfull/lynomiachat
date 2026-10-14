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

  it "never connects another account's flow to an inbox, and never shows the bot's secret or token" do
    other = create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') }
    foreign = create(:agent_bot, account: other, bot_type: :flow, outgoing_url: nil)
    post "/api/v1/accounts/#{account.id}/inboxes/#{whatsapp.inbox.id}/set_agent_bot", params: { agent_bot: foreign.id },
                                                                                      headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(whatsapp.inbox.reload.agent_bot).to be_nil

    get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(flow.secret)
    expect(response.body).not_to include(flow.access_token.token)
  end

  it 'creates a flow bot, saves its draft, refuses to publish an invalid one, and publishes a valid one' do
    post base, params: { name: 'Welcome', description: 'Main menu' }, headers: admin.create_new_auth_token, as: :json
    created = response.parsed_body
    expect(AgentBot.find(created['id'])).to have_attributes(bot_type: 'flow', account_id: account.id, outgoing_url: nil)
    expect(created['graph']['nodes'].pluck('type')).to eq(%w[start end])

    put "#{base}/#{created['id']}/draft", params: { graph: { nodes: 'x' }, lock_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['errors'].pluck('code')).to eq(['invalid_graph'])

    broken = menu_graph.merge(edges: menu_graph[:edges].first(2))
    put "#{base}/#{created['id']}/draft", params: { graph: broken, lock_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['errors'].pluck('code')).to include('unconnected_output')
    post "#{base}/#{created['id']}/publish", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    # The save above moved the draft on, so the next one carries the lock_version it answered
    # with. An editor that kept sending the value it first loaded is the lost update this
    # precondition exists to refuse.
    saved = response.parsed_body['draft'] || { 'lock_version' => 1 }
    put "#{base}/#{created['id']}/draft", params: { graph: menu_graph, lock_version: saved['lock_version'] },
                                          headers: admin.create_new_auth_token, as: :json
    post "#{base}/#{created['id']}/publish", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['published']).to include('version' => 1, 'status' => 'published')
  end

  # THE CONTRACT A SECOND EDITOR IS BUILT AGAINST.
  #
  # GET /flows/:id serves the node catalogue, the channel limits and the variable suggestions, and
  # Phase 4's native Store Syria Automation Studio renders its palette and config panel FROM them
  # rather than hardcoding node schemas. No backend spec asserted any of those keys, so renaming
  # one broke nothing here and everything there. This is that assertion.
  describe 'the builder contract' do
    before { get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json }

    it 'serves the node catalogue a client builds its palette from' do
      types = response.parsed_body['node_types']

      # Every type the runtime knows, and no others: a client offering a node the runner cannot
      # execute is a client offering a flow that fails at publish.
      expect(types.keys).to match_array(Flows::NodeTypes::TYPES.keys)
      expect(types['send_message']).to eq('outputs' => ['next'], 'data' => ['text'])
      # The facets the editor needs to draw a node: its handles, which may be left unconnected,
      # and whether it waits.
      expect(types['question']).to include('outputs' => %w[reply invalid timeout],
                                           'optional' => %w[invalid timeout], 'wait' => true)
      # A node whose handles come from its own config rather than a fixed list.
      expect(types['buttons']).to include('outputs' => 'options', 'extra' => %w[other timeout])
    end

    it 'serves the channel limits the config panel validates input against' do
      expect(response.parsed_body['capabilities']).to include(
        'text' => { 'body' => 4096 },
        'buttons' => { 'max' => 3, 'title' => 20, 'body' => 1024 }
      )
    end

    it 'serves the variables a client offers for interpolation' do
      expect(response.parsed_body['variables']).to eq(Flows::Variables::SUGGESTED.as_json)
    end

    it 'serves a starter graph for a flow that has never been edited' do
      expect(response.parsed_body['graph']['nodes'].pluck('type')).to eq(%w[start end])
      expect(response.parsed_body['errors']).to eq([])
    end
  end

  # WHY A CLIENT CAN SAY "UNAVAILABLE, BECAUSE". `capabilities` is what the editor authors
  # against and is deliberately unconditional -- a flow is written before it is connected, and a
  # new flow with no inbox still needs those limits. `channel_eligibility` is the other half:
  # what this flow's OWN inboxes can really run.
  describe 'channel eligibility' do
    let(:email) { create(:channel_email, account: account).inbox }

    it 'is empty while the flow is connected to nothing, and capabilities are still offered' do
      get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['channel_eligibility']).to eq([])
      expect(response.parsed_body['capabilities']).to include('text' => { 'body' => 4096 })
    end

    it 'reports a WhatsApp Cloud inbox as able to run flows' do
      create(:agent_bot_inbox, inbox: whatsapp.inbox, agent_bot: flow, account: account)

      get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['channel_eligibility'].sole)
        .to include('id' => whatsapp.inbox.id, 'runs_flows' => true, 'unsupported_nodes' => [])
    end

    # Flows run on WhatsApp Cloud and nowhere else today. A client that offered a flow on an
    # email inbox would be offering something publish refuses, so the answer says so here.
    it 'reports an inbox that cannot run flows at all, rather than implying it can' do
      create(:agent_bot_inbox, inbox: email, agent_bot: flow, account: account)
      Flows::Versions.new(flow).save!(menu_graph.deep_stringify_keys, lock_version: 0)

      get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
      row = response.parsed_body['channel_eligibility'].sole

      expect(row).to include('channel_type' => 'Channel::Email', 'runs_flows' => false)
      expect(row['unsupported_nodes']).to include('buttons')
    end
  end

  # TWO PEOPLE EDITING ONE FLOW.
  #
  # Before this precondition existed, the draft save was `version.update!(graph: graph)` with
  # nothing in front of it: the second person to press Save overwrote the first with a graph
  # built from a view of the flow that no longer existed, and neither of them was told. Lost
  # work, silently, which is the worst way to lose it.
  describe 'concurrent editing' do
    let(:save_draft) do
      lambda do |graph, lock_version, user = admin|
        put "#{base}/#{flow.id}/draft", params: { graph: graph, lock_version: lock_version },
                                        headers: user.create_new_auth_token, as: :json
      end
    end
    let(:other_graph) { menu_graph.merge(nodes: menu_graph[:nodes].map { |n| n[:id] == 'track' ? n.merge(data: { text: 'theirs' }) : n }) }
    let(:mine) { menu_graph.merge(nodes: menu_graph[:nodes].map { |n| n[:id] == 'track' ? n.merge(data: { text: 'mine' }) : n }) }

    it 'refuses the second save and keeps the first editor\'s work' do
      # Both editors loaded the flow at the same moment, so both hold the same lock_version.
      get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
      loaded = response.parsed_body['draft']&.fetch('lock_version', 0) || 0

      save_draft.call(other_graph, loaded)
      expect(response).to have_http_status(:success)

      save_draft.call(mine, loaded)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('flow_draft_stale')
      # Theirs survived; mine did not land.
      expect(flow.flow_versions.draft.sole.graph['nodes'].find { |n| n['id'] == 'track' }['data']['text']).to eq('theirs')
    end

    # The refusal carries what is actually stored, so the editor can show the other person's
    # version and let someone reapply their own work, instead of making them reload and retype.
    it 'answers the conflict with the current graph and the lock_version to retry with' do
      get "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
      loaded = response.parsed_body['draft']&.fetch('lock_version', 0) || 0
      save_draft.call(other_graph, loaded)

      save_draft.call(mine, loaded)
      conflict = response.parsed_body

      expect(conflict['graph']['nodes'].find { |n| n['id'] == 'track' }['data']['text']).to eq('theirs')
      save_draft.call(mine, conflict['lock_version'])
      expect(response).to have_http_status(:success)
      expect(flow.flow_versions.draft.sole.graph['nodes'].find { |n| n['id'] == 'track' }['data']['text']).to eq('mine')
    end

    # AN OPTIONAL PRECONDITION IS NOT A PRECONDITION. A caller that simply omits it -- an old
    # client, a script, anyone who noticed -- would be back to overwriting the other editor.
    it 'refuses a save that carries no lock_version at all' do
      put "#{base}/#{flow.id}/draft", params: { graph: menu_graph }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flow.flow_versions.draft).to be_empty
    end

    it 'refuses a lock_version that is not a number' do
      ['abc', '-1', '1; DROP TABLE flow_versions', ''].each do |bad|
        put "#{base}/#{flow.id}/draft", params: { graph: menu_graph, lock_version: bad },
                                        headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity), bad
      end
    end
  end

  it 'deletes only a flow that is not published' do
    Flows::Versions.new(flow).tap { |versions| versions.save!(menu_graph.deep_stringify_keys, lock_version: 0) }.publish!

    delete "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['errors'].pluck('code')).to eq(['flow_active'])

    post "#{base}/#{flow.id}/disable", headers: admin.create_new_auth_token, as: :json
    delete "#{base}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
    expect(AgentBot.exists?(flow.id)).to be(false)
  end

  it 'tests the draft on the real runtime and keeps nothing: no message, conversation, contact or job' do
    AgentBotInbox.create!(inbox: whatsapp.inbox, agent_bot: flow)
    Flows::Versions.new(flow).save!(menu_graph.deep_stringify_keys, lock_version: 0)
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
    version = Flows::Versions.new(flow).tap { |versions| versions.save!(menu_graph.deep_stringify_keys, lock_version: 0) }.publish!
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
