require 'rails_helper'

# Buttons and List (docs/flow-builder/04-node-contracts.md §choices): sent as Chatwoot input_select messages, routed by the
# option id WhatsApp returns, never by the visible title alone.
RSpec.describe Flows::Nodes::Choice do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966500000002') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:edge) { ->(source, handle, target) { { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target } } }
  let(:menu_graph) do
    lambda do |type, data = {}, other: false|
      options = [{ 'id' => 'track', 'title' => 'Track order' }, { 'id' => 'care', 'title' => 'Customer care' }]
      graph = { 'nodes' => [node.call('start', 'start'), node.call('menu', type, { 'text' => 'How can we help?', 'options' => options }.merge(data)),
                            node.call('track', 'send_message', 'text' => 'Tracking'), node.call('care', 'send_message', 'text' => 'Care'),
                            node.call('end', 'end')],
                'edges' => [edge.call('start', 'next', 'menu'), edge.call('menu', 'track', 'track'), edge.call('menu', 'care', 'care'),
                            edge.call('track', 'next', 'end'), edge.call('care', 'next', 'end')] }
      return graph unless other

      graph['nodes'] << node.call('else', 'send_message', 'text' => 'Something else')
      graph['edges'] += [edge.call('menu', 'other', 'else'), edge.call('else', 'next', 'end')]
      graph
    end
  end
  let(:publish) { ->(graph) { Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish! } }
  let(:incoming) do
    lambda do |text, reply_id = nil|
      attributes = reply_id ? { interactive_reply: { type: 'button_reply', id: reply_id, title: text } } : {}
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact, content: text,
                       content_attributes: attributes)
    end
  end
  let(:run) { ->(message) { Flows::RunJob.perform_now(conversation.id, 'messages', message.id) } }
  let(:bot_messages) { -> { conversation.messages.outgoing.where(sender: bot).order(:id) } }

  before { AgentBotInbox.create!(inbox: inbox, agent_bot: bot) }

  it 'sends the buttons with option values of this node, and follows the option id WhatsApp returns' do
    publish.call(menu_graph.call('buttons'))
    run.call(incoming.call('hi'))

    menu = bot_messages.call.last
    expect(menu).to have_attributes(content_type: 'input_select', content: 'How can we help?')
    expect(menu.content_attributes['items']).to eq([{ 'title' => 'Track order', 'value' => 'lfb:menu:track' },
                                                    { 'title' => 'Customer care', 'value' => 'lfb:menu:care' }])

    run.call(incoming.call('Track order', 'lfb:menu:care'))

    expect(bot_messages.call.last.content).to eq('Care')
    expect(FlowSession.find_by(conversation: conversation)).to be_completed
  end

  it 'accepts a typed title or the option number, Arabic digits included' do
    publish.call(menu_graph.call('buttons'))
    run.call(incoming.call('hi'))
    run.call(incoming.call('  customer CARE '))
    expect(bot_messages.call.last.content).to eq('Care')

    run.call(incoming.call('hi'))
    run.call(incoming.call('١'))
    expect(bot_messages.call.last.content).to eq('Tracking')
  end

  it 'never matches a reply id sent for another menu' do
    publish.call(menu_graph.call('buttons', other: true))
    run.call(incoming.call('hi'))

    run.call(incoming.call('Customer care', 'lfb:old_menu:care'))

    expect(bot_messages.call.last.content).to eq('Something else')
  end

  it 'sends the menu again for an unknown answer, then hands the conversation to humans' do
    publish.call(menu_graph.call('buttons'))
    run.call(incoming.call('hi'))

    3.times { |index| run.call(incoming.call("what #{index}")) }

    expect(bot_messages.call.pluck(:content)).to eq(['How can we help?'] * 3)
    expect(FlowSession.find_by(conversation: conversation)).to have_attributes(status: 'handed_off', context: include('end_reason' => 'no_choice'))
    expect(conversation.reload).to be_open
  end

  it 'sends a List as a WhatsApp list with its own button label, even for two short options' do
    publish.call(menu_graph.call('list', { 'button_label' => 'Choose' }))
    run.call(incoming.call('hi'))
    menu = bot_messages.call.last
    expect(menu.content_attributes).to include('interactive_type' => 'list', 'list_button' => 'Choose')

    stub = stub_request(:post, "https://graph.facebook.com/#{Whatsapp::FacebookApiClient::DEFAULT_API_VERSION}/123456789/messages").with do |request|
      interactive = JSON.parse(request.body)['interactive']
      action = JSON.parse(interactive['action'])
      rows = action.dig('sections', 0, 'rows').pluck('id')
      interactive['type'] == 'list' && action['button'] == 'Choose' && rows == %w[lfb:menu:track lfb:menu:care]
    end.to_return(status: 200, body: { messages: [{ id: 'wamid.list' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: whatsapp).send_message('+966500000002', menu)
    expect(stub).to have_been_requested
  end
end
