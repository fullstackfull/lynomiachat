require 'rails_helper'

# Flow Builder security (docs/flow-builder/08-security-and-tenancy.md): what customers type never becomes a template,
# attribute patterns cannot stall a worker, graphs are bounded, versions and sessions stay in their account, and the
# webhook payload carries no secret.
RSpec.describe Flows::Runner do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account, email: 'private@example.com') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '966500000012'))
  end
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:edge) do
    ->(source, target, handle = 'next') { { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target } }
  end
  let(:say) do
    lambda do |text|
      message = create(:message, conversation: conversation, account: account, inbox: whatsapp.inbox, message_type: :incoming,
                                 sender: contact, content: text)
      Flows::RunJob.perform_now(conversation.id, 'messages', message.id)
    end
  end

  before { AgentBotInbox.create!(inbox: whatsapp.inbox, agent_bot: bot) }

  it 'never renders what a customer typed as a template, whatever they put in it' do
    graph = { 'nodes' => [node.call('start', 'start'),
                          node.call('ask', 'question', 'text' => 'Your name?', 'store_as' => { 'scope' => 'context', 'key' => 'name' }),
                          node.call('echo', 'send_message', 'text' => 'Hello {{flow.name}}'), node.call('end', 'end')],
              'edges' => [edge.call('start', 'ask'), edge.call('ask', 'echo', 'reply'), edge.call('echo', 'end')] }
    Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish!

    say.call('hi')
    say.call('{{contact.email}} {% if true %}x{% endif %}')

    reply = conversation.messages.outgoing.where(sender: bot).order(:id).last.content
    expect(reply).not_to include('private@example.com')
    expect(reply).not_to include('{%')
    expect(reply).to eq('Hello contact.email  if true x endif ')
  end

  it 'gives up on a catastrophic attribute pattern instead of stalling the worker' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'code',
                                                      attribute_display_type: :text, regex_pattern: '/^(a+)+$/')

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(Flows::AttributeValue.cast(definition, "#{'a' * 40}!")).to be_nil
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
  end

  it 'refuses graphs beyond the size limits before reading them' do
    many = { 'nodes' => Array.new(Flows::GraphValidator::MAX_NODES + 1) { |index| node.call("n#{index}", 'end') }, 'edges' => [] }
    huge = { 'nodes' => [node.call('start', 'start', 'keywords' => ['x' * 600_000])], 'edges' => [] }

    expect(Flows::GraphValidator.new(account, many).shape_errors.pluck(:code)).to eq(['too_many_nodes'])
    expect(Flows::GraphValidator.new(account, huge).shape_errors.pluck(:code)).to eq(['graph_too_large'])
  end

  it "never resumes a session from another conversation's message or timer" do
    graph = { 'nodes' => [node.call('start', 'start'), node.call('ask', 'question', 'text' => 'Your order?', 'timeout_minutes' => 5),
                          node.call('done', 'send_message', 'text' => 'Thanks'), node.call('end', 'end')],
              'edges' => [edge.call('start', 'ask'), edge.call('ask', 'done', 'reply'), edge.call('done', 'end')] }
    Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish!
    say.call('hi')
    session = FlowSession.find_by!(conversation: conversation)
    other_contact = create(:contact, account: account)
    other = create(:conversation, account: account, inbox: whatsapp.inbox, contact: other_contact,
                                  contact_inbox: create(:contact_inbox, contact: other_contact, inbox: whatsapp.inbox, source_id: '966500000013'))
    stray = create(:message, conversation: other, account: account, inbox: whatsapp.inbox, message_type: :incoming, sender: other_contact,
                             content: '42')

    described_class.new(conversation).messages(stray)
    Flows::RunJob.perform_now(other.id, 'wake', nil, session.id, session.step_token)

    expect(session.reload).to have_attributes(status: 'waiting', current_node_id: 'ask', last_message_id: session.last_message_id)
    expect(FlowSession.where(conversation: other)).to be_empty
    expect(conversation.messages.outgoing.pluck(:content)).to eq(['Your order?'])
  end

  it 'keeps versions and sessions in the bot\'s account' do
    other = create(:account)
    foreign_bot = create(:agent_bot, account: other, bot_type: :flow, outgoing_url: nil)
    version = Flows::Versions.new(bot).draft

    expect(FlowVersion.new(account: account, agent_bot: foreign_bot, version: 9, graph: {})).not_to be_valid
    expect(FlowSession.new(account: other, agent_bot: bot, flow_version: version, conversation: conversation, status: :active,
                           current_node_id: 'start')).not_to be_valid
  end

  it 'posts no secret in the webhook payload, and a flow cannot name a variable outside the allow-list' do
    graph = { 'nodes' => [node.call('start', 'start'), node.call('hook', 'webhook', 'url' => 'https://hooks.example.com/flow'),
                          node.call('end', 'end')],
              'edges' => [edge.call('start', 'hook'), edge.call('hook', 'end')] }
    Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish!

    expect { say.call('hi') }.to have_enqueued_job(WebhookJob).with do |_url, payload, _type, **options|
      expect(payload.to_json).not_to include(bot.secret)
      expect(options[:secret]).to eq(bot.secret)
    end
    expect(Flows::Variables.unknown('{{contact.access_token}} {{account.secret}} {{flow.order.total}}'))
      .to eq(['contact.access_token', 'account.secret', 'flow.order.total'])
  end
end
