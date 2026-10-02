require 'rails_helper'

# Webhook, Delay, Human Handoff and Go To on the runtime (docs/flow-builder/04-node-contracts.md,
# 05-runtime-and-session.md), and the runtime limits that stop a looping graph even if one were ever published.
RSpec.describe Flows::Runner do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966500000005'))
  end
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:edge) do
    ->(source, target, handle = 'next') { { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target } }
  end
  let(:publish) { ->(graph) { Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish! } }
  let(:say) do
    lambda do |text|
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact, content: text)
      Flows::RunJob.perform_now(conversation.id, 'messages', message.id)
      FlowSession.where(conversation: conversation).order(:id).last
    end
  end
  let(:bot_texts) { -> { conversation.messages.outgoing.where(sender: bot, private: false).order(:id).pluck(:content) } }

  before { AgentBotInbox.create!(inbox: inbox, agent_bot: bot) }

  it 'posts the flow state to a webhook, signed with the bot secret, and goes on without waiting for it' do
    publish.call('nodes' => [node.call('start', 'start'), node.call('hook', 'webhook', 'url' => 'https://n8n.example.com/webhook/lynomia'),
                             node.call('end', 'end')],
                 'edges' => [edge.call('start', 'hook'), edge.call('hook', 'end')])

    expect { expect(say.call('hello')).to be_completed }
      .to have_enqueued_job(WebhookJob).with('https://n8n.example.com/webhook/lynomia',
                                             hash_including(event: 'flow_webhook', reply: 'hello',
                                                            flow: hash_including(id: bot.id, node_id: 'hook')),
                                             :flow_webhook, secret: bot.secret, delivery_id: kind_of(String))
  end

  it 'waits on a timer for a delay, ignores messages meanwhile, and resumes once' do
    publish.call('nodes' => [node.call('start', 'start'), node.call('a', 'send_message', 'text' => 'first'),
                             node.call('wait', 'delay', 'seconds' => 60), node.call('b', 'send_message', 'text' => 'second'),
                             node.call('end', 'end')],
                 'edges' => [edge.call('start', 'a'), edge.call('a', 'wait'), edge.call('wait', 'b'), edge.call('b', 'end')])

    session = say.call('hi')
    wake_at = session.wake_at
    expect(session).to have_attributes(status: 'waiting', current_node_id: 'wait')
    expect(wake_at).to be_within(5.seconds).of(60.seconds.from_now)

    say.call('are you there?')
    stale = session.step_token
    expect(session.reload).to have_attributes(status: 'waiting', wake_at: wake_at)
    expect(bot_texts.call).to eq(['first'])

    Flows::RunJob.perform_now(conversation.id, 'wake', nil, session.id, stale)
    expect(bot_texts.call).to eq(['first'])
    2.times { Flows::RunJob.perform_now(conversation.id, 'wake', nil, session.id, session.reload.step_token) }
    expect(bot_texts.call).to eq(%w[first second])
    expect(session.reload).to be_completed
  end

  it 'hands off with routing and a note for agents, and stays silent afterwards' do
    team = create(:team, account: account)
    create(:label, account: account, title: 'care')
    publish.call('nodes' => [node.call('start', 'start'),
                             node.call('human', 'handoff', 'team_id' => team.id, 'priority' => 'high', 'labels' => ['care'],
                                                           'reason' => 'Asked for customer care')],
                 'edges' => [edge.call('start', 'human')])

    session = say.call('agent please')

    expect(session).to have_attributes(status: 'handed_off', context: include('end_reason' => 'handoff_node'))
    expect(conversation.reload).to have_attributes(status: 'open', team_id: team.id, priority: 'high', label_list: ['care'], ai_assignee: nil)
    expect(conversation.messages.where(private: true).pluck(:content)).to eq(['Asked for customer care'])

    say.call('hello?')
    expect(FlowSession.where(conversation: conversation).count).to eq(1)
    expect(bot_texts.call).to eq([])
  end

  it 'follows Go To, and fails a looping graph at the visit limit even if it bypassed validation' do
    publish.call('nodes' => [node.call('start', 'start'), node.call('jump', 'goto', 'target' => 'end'), node.call('end', 'end')],
                 'edges' => [edge.call('start', 'jump')])
    expect(say.call('hi')).to be_completed

    create(:label, account: account, title: 'loop')
    looping = { 'nodes' => [node.call('start', 'start'), node.call('tag', 'add_label', 'labels' => ['loop']),
                            node.call('again', 'goto', 'target' => 'tag')],
                'edges' => [edge.call('start', 'tag'), edge.call('tag', 'again')] }
    expect(Flows::GraphValidator.new(account, looping).errors.pluck(:code)).to include('loop_without_wait')
    bot.published_flow_version.update!(status: :archived)
    FlowVersion.create!(account: account, agent_bot: bot, version: 99, graph: looping).update!(status: :published)

    session = say.call('hi again')
    expect(session).to have_attributes(status: 'failed', failure_code: 'visit_limit')
    expect(session.context.dig('visits', 'tag')).to eq(described_class::MAX_NODE_VISITS)
    expect(conversation.reload).to be_open
  end
end
