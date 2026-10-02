require 'rails_helper'

# Attribute, label and assignment nodes (docs/flow-builder/04-node-contracts.md): Chatwoot's own writes and actions
# (ActionService), limited to the account, run by the flow on its conversation.
RSpec.describe Flows::Nodes::SetAttribute do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966500000004'))
  end
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:chain) do
    lambda do |*nodes|
      edges = nodes.each_cons(2).map do |from, to|
        { 'id' => "#{from['id']}-next", 'source' => from['id'], 'sourceHandle' => 'next', 'target' => to['id'] }
      end
      { 'nodes' => [node.call('start', 'start')] + nodes, 'edges' => [edges, { 'id' => 's', 'source' => 'start', 'sourceHandle' => 'next',
                                                                               'target' => nodes.first['id'] }].flatten }
    end
  end
  let(:start) do
    lambda do |graph, text = 'hi'|
      Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish!
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact, content: text)
      Flows::RunJob.perform_now(conversation.id, 'messages', message.id)
      FlowSession.find_by(conversation: conversation)
    end
  end

  before do
    AgentBotInbox.create!(inbox: inbox, agent_bot: bot)
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'tier', attribute_display_type: :text)
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'order_no',
                                         attribute_display_type: :number)
    %w[vip support].each { |title| create(:label, account: account, title: title) }
  end

  it 'writes attributes, adds labels once, removes labels and queues a team, keeping the conversation with the flow' do
    team = create(:team, account: account)
    conversation.update!(label_list: ['support'])
    session = start.call(chain.call(node.call('tier', 'set_contact_attribute', 'key' => 'tier', 'value' => 'gold'),
                                    node.call('no', 'set_conversation_attribute', 'key' => 'order_no', 'value' => '{{flow.reply}}'),
                                    node.call('vip', 'add_label', 'labels' => ['vip']), node.call('again', 'add_label', 'labels' => %w[vip]),
                                    node.call('unsupport', 'remove_label', 'labels' => ['support']),
                                    node.call('team', 'assign_team', 'team_id' => team.id.to_s), node.call('end', 'end')), '١٠٢٣')

    expect(session).to be_completed
    expect(contact.reload.custom_attributes).to include('tier' => 'gold')
    expect(conversation.reload).to have_attributes(label_list: ['vip'], team_id: team.id, status: 'pending',
                                                   custom_attributes: { 'order_no' => 1023 })
  end

  it 'fails the session and gives the conversation to humans when a value does not fit the attribute' do
    session = start.call(chain.call(node.call('no', 'set_conversation_attribute', 'key' => 'order_no', 'value' => '{{flow.reply}}'),
                                    node.call('end', 'end')), 'my order')

    expect(session).to have_attributes(status: 'failed', failure_code: 'invalid_attribute_value')
    expect(conversation.reload).to have_attributes(status: 'open', custom_attributes: {})
  end

  it 'assigns an agent of the inbox, sends what follows, then hands the conversation to that agent' do
    agent = create(:user, account: account, role: :agent, name: 'Sara')
    create(:inbox_member, inbox: inbox, user: agent)
    session = start.call(chain.call(node.call('sara', 'assign_agent', 'agent_id' => agent.id),
                                    node.call('note', 'send_message', 'text' => 'Sara will help'), node.call('end', 'end')))

    expect(conversation.messages.outgoing.where(sender: bot).pluck(:content)).to eq(['Sara will help'])
    expect(session).to have_attributes(status: 'handed_off', context: include('end_reason' => 'human_assigned'))
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
  end

  it 'follows failed for an agent outside the inbox' do
    outsider = create(:user, account: account, role: :agent)
    graph = chain.call(node.call('who', 'assign_agent', 'agent_id' => outsider.id), node.call('end', 'end'))
    graph['nodes'] << node.call('nobody', 'send_message', 'text' => 'No agent')
    graph['edges'] << { 'id' => 'who-failed', 'source' => 'who', 'sourceHandle' => 'failed', 'target' => 'nobody' }
    graph['edges'] << { 'id' => 'nobody-next', 'source' => 'nobody', 'sourceHandle' => 'next', 'target' => 'end' }

    expect(start.call(graph)).to be_completed
    expect(conversation.messages.outgoing.where(sender: bot).pluck(:content)).to eq(['No agent'])
    expect(conversation.reload.assignee_id).to be_nil
  end
end
