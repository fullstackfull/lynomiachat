require 'rails_helper'

# The flow runtime (docs/flow-builder/05-runtime-and-session.md): Chatwoot's bot phase, sessions bound to a published
# version, messages consumed once and in order, the conversation's lock, human takeover, the switch.
RSpec.describe Flows::RunJob do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account, name: 'Omar') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966500000001') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:edge) { ->(source, handle, target) { { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target } } }
  let(:publish) { ->(graph) { Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish! } }
  let(:incoming) do
    ->(text) { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact, content: text) }
  end
  let(:run) { ->(message) { described_class.perform_now(conversation.id, 'messages', message.id) } }
  let(:bot_texts) { -> { conversation.messages.outgoing.where(sender: bot).order(:id).pluck(:content) } }
  let(:ask_graph) do
    { 'nodes' => [node.call('start', 'start'), node.call('hi', 'send_message', 'text' => 'Hello {{contact.name}}'),
                  node.call('ask', 'question', 'text' => 'Your order number?', 'reply_type' => 'number',
                                               'store_as' => { 'scope' => 'context', 'key' => 'order_no' }),
                  node.call('thanks', 'send_message', 'text' => 'Looking up {{flow.order_no}}'), node.call('end', 'end')],
      'edges' => [edge.call('start', 'next', 'hi'), edge.call('hi', 'next', 'ask'), edge.call('ask', 'reply', 'thanks'),
                  edge.call('thanks', 'next', 'end')] }
  end

  before { AgentBotInbox.create!(inbox: inbox, agent_bot: bot) }

  it 'starts in the bot phase, sends through Chatwoot messages, waits for the reply, resumes once, and completes' do
    publish.call(ask_graph)
    expect(conversation).to have_attributes(status: 'pending', ai_assignee: bot)

    first = incoming.call('hi')
    run.call(first)
    session = FlowSession.find_by(conversation: conversation)
    expect(session).to have_attributes(status: 'waiting', current_node_id: 'ask', last_message_id: first.id)
    expect(bot_texts.call).to eq(['Hello Omar', 'Your order number?'])

    reply = incoming.call('١٠٢٣')
    2.times { run.call(reply) }
    expect(session.reload).to have_attributes(status: 'completed', last_message_id: reply.id)
    expect(bot_texts.call).to eq(['Hello Omar', 'Your order number?', 'Looking up 1023'])
    expect(conversation.reload).to be_pending
  end

  it 'consumes replies that arrive together in order, each once, whichever job runs first' do
    publish.call(ask_graph)
    run.call(incoming.call('hi'))
    wrong = incoming.call('not a number')
    right = incoming.call('77')

    run.call(right)
    run.call(wrong)

    expect(bot_texts.call).to eq(['Hello Omar', 'Your order number?', 'Your order number?', 'Looking up 77'])
    expect(FlowSession.where(conversation: conversation).count).to eq(1)
  end

  it 'keeps a running session on its version when a new version is published' do
    first_version = publish.call(ask_graph)
    run.call(incoming.call('hi'))
    v2 = ask_graph['nodes'].map { |item| item['id'] == 'thanks' ? item.merge('data' => { 'text' => 'v2' }) : item }
    publish.call(ask_graph.merge('nodes' => v2))

    run.call(incoming.call('5'))

    expect(FlowSession.last.flow_version).to eq(first_version)
    expect(bot_texts.call.last).to eq('Looking up 5')
  end

  it 'refuses to advance while another worker holds the conversation lock' do
    publish.call(ask_graph)
    message = incoming.call('hi')
    Redis::LockManager.new.lock(format(described_class::LOCK_KEY, id: conversation.id), 10)

    expect { described_class.new(conversation.id, 'messages', message.id).perform(conversation.id, 'messages', message.id) }
      .to raise_error(MutexApplicationJob::LockAcquisitionError)
    expect(FlowSession.count).to eq(0)
  ensure
    Redis::LockManager.new.unlock(format(described_class::LOCK_KEY, id: conversation.id))
  end

  it 'stops for a human: an agent reply hands the conversation over and the bot never answers again' do
    publish.call(ask_graph)
    run.call(incoming.call('hi'))
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: agent)
    human = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                             content: 'Hi, Sara here')

    described_class.perform_now(conversation.id, 'human', human.id)
    run.call(incoming.call('12'))

    expect(FlowSession.last).to have_attributes(status: 'handed_off')
    expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: nil)
    expect(bot_texts.call).to eq(['Hello Omar', 'Your order number?'])
  end

  it 'hands the conversation over when the start does not match, nothing is published, or flows are switched off' do
    keyword_start = ask_graph['nodes'].map { |item| item['id'] == 'start' ? item.merge('data' => { 'keywords' => ['order'] }) : item }
    publish.call(ask_graph.merge('nodes' => keyword_start))
    run.call(incoming.call('hello'))
    expect(conversation.reload).to be_open
    expect(FlowSession.count).to eq(0)

    conversation.update!(status: :pending, ai_assignee: bot)
    with_modified_env LYNOMIA_FLOW_BUILDER_ENABLED: 'false' do
      run.call(incoming.call('my order'))
    end
    expect(conversation.reload).to be_open
    expect(bot_texts.call).to be_empty
  end

  it 'does nothing for a blocked contact but hand over, and nothing at all without the feature' do
    publish.call(ask_graph)
    contact.update!(blocked: true)
    run.call(incoming.call('hi'))
    expect(bot_texts.call).to be_empty

    account.disable_features!('lynomia_flow_builder')
    conversation.update!(status: :pending, ai_assignee: bot)
    contact.update!(blocked: false)
    run.call(incoming.call('hi'))
    expect(bot_texts.call).to be_empty
  end

  it 'cancels the session when someone resolves the conversation, and ignores a stale timer' do
    timed = ask_graph['nodes'].map { |item| item['id'] == 'ask' ? item.merge('data' => item['data'].merge('timeout_minutes' => 5)) : item }
    publish.call(ask_graph.merge('nodes' => timed))
    run.call(incoming.call('hi'))
    session = FlowSession.last
    token = session.step_token

    conversation.resolved!
    described_class.perform_now(conversation.id, 'stop')
    described_class.perform_now(conversation.id, 'wake', nil, session.id, token)

    expect(session.reload).to have_attributes(status: 'cancelled')
    expect(bot_texts.call).to eq(['Hello Omar', 'Your order number?'])
  end
end
