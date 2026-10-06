require 'rails_helper'

# Send WhatsApp template (docs/flow-builder/04-node-contracts.md §send template): the flow creates the message the
# dashboard composer would (template_params, raw_template), and Chatwoot's WhatsApp path sends it.
RSpec.describe Flows::Nodes::SendTemplate do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:whatsapp) do
    templates =
      [
        { 'name' => 'order_update', 'language' => 'en', 'status' => 'APPROVED', 'category' => 'UTILITY', 'namespace' => 'ns-1',
          'components' => [
            { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order {{1}}' },
            { 'type' => 'BODY', 'text' => 'Hi {{1}}, your order {{2}} is {{3}}.' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Track', 'url' => 'https://shop.example.com/t/{{1}}' },
                                                 { 'type' => 'QUICK_REPLY', 'text' => 'Thanks' }] }
          ] },
        { 'name' => 'welcome_back', 'language' => 'ar', 'status' => 'APPROVED', 'category' => 'MARKETING', 'parameter_format' => 'NAMED',
          'components' => [{ 'type' => 'BODY', 'text' => 'أهلاً {{customer}}' }] }
      ]
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false,
                              message_templates: templates)
  end
  let(:inbox) { whatsapp.inbox }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account, name: 'Omar', email: nil) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966500000007'))
  end
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:edge) do
    ->(source, target, handle = 'next') { { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target } }
  end
  let(:order_update) do
    { 'name' => 'order_update', 'language' => 'en',
      'params' => { 'header' => { '1' => '{{flow.reply}}' }, 'body' => { '1' => '{{contact.name}}', '2' => '{{flow.reply}}', '3' => 'shipped' },
                    'buttons' => [{ 'type' => 'url', 'parameter' => '{{flow.reply}}' }] } }
  end
  let(:publish) { ->(graph) { Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish! } }
  let(:straight) do
    lambda do |data|
      publish.call('nodes' => [node.call('start', 'start'), node.call('tpl', 'send_template', data), node.call('end', 'end')],
                   'edges' => [edge.call('start', 'tpl'), edge.call('tpl', 'end')])
    end
  end
  let(:say) do
    lambda do |text|
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact, content: text)
      Flows::RunJob.perform_now(conversation.id, 'messages', message.id)
      FlowSession.where(conversation: conversation).order(:id).last
    end
  end
  let(:bot_messages) { -> { conversation.messages.outgoing.where(sender: bot, private: false).order(:id) } }
  let(:graph_calls) { [] }

  before do
    AgentBotInbox.create!(inbox: inbox, agent_bot: bot)
    stub_request(:post, %r{\Ahttps://graph.facebook.com/#{Whatsapp::FacebookApiClient::DEFAULT_API_VERSION}/\w+/messages\z}o).to_return do |request|
      graph_calls << JSON.parse(request.body)
      { status: 200, body: { messages: [{ id: "wamid.#{graph_calls.size}" }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  it 'creates the template message the composer would, with the run values, and Chatwoot sends it as a template' do
    straight.call(order_update)

    expect(say.call('A-100')).to be_completed
    message = bot_messages.call.sole
    expect(message.content).to eq('Hi Omar, your order A-100 is shipped.')
    expect(message.additional_attributes['template_params']).to include(
      'name' => 'order_update', 'language' => 'en', 'namespace' => 'ns-1', 'category' => 'UTILITY',
      'processed_params' => { 'header' => { '1' => 'A-100' }, 'body' => { '1' => 'Omar', '2' => 'A-100', '3' => 'shipped' },
                              'buttons' => [{ 'type' => 'url', 'parameter' => 'A-100' }] }
    )

    Whatsapp::SendOnWhatsappService.new(message: message).perform
    expect(graph_calls.sole).to include('type' => 'template', 'to' => '966500000007')
    expect(graph_calls.sole['template']).to include('name' => 'order_update', 'language' => { 'policy' => 'deterministic', 'code' => 'en' })
    expect(graph_calls.sole.dig('template', 'components')).to eq(
      [{ 'type' => 'header', 'parameters' => [{ 'type' => 'text', 'text' => 'A-100' }] },
       { 'type' => 'body', 'parameters' => [{ 'type' => 'text', 'text' => 'Omar' }, { 'type' => 'text', 'text' => 'A-100' },
                                            { 'type' => 'text', 'text' => 'shipped' }] },
       { 'type' => 'button', 'sub_type' => 'url', 'index' => 0, 'parameters' => [{ 'type' => 'text', 'text' => 'A-100' }] }]
    )
    expect(message.reload).to have_attributes(source_id: 'wamid.1', status: 'sent')
  end

  it 'fills named parameters, and a customer reply never becomes a template' do
    straight.call('name' => 'welcome_back', 'language' => 'AR', 'params' => { 'body' => { 'customer' => '{{flow.reply}}' } })

    say.call('{{account.name}} {% raw %}')

    expect(bot_messages.call.sole.additional_attributes.dig('template_params', 'processed_params'))
      .to eq('body' => { 'customer' => 'account.name  raw' })
  end

  it 'goes out after the 24-hour window, where Chatwoot refuses free-form messages' do
    publish.call('nodes' => [node.call('start', 'start'), node.call('ask', 'question', 'text' => 'Your order number?', 'timeout_minutes' => 1440),
                             node.call('tpl', 'send_template', order_update), node.call('end', 'end')],
                 'edges' => [edge.call('start', 'ask'), edge.call('ask', 'end', 'reply'), edge.call('ask', 'tpl', 'timeout'),
                             edge.call('tpl', 'end')])
    session = say.call('hi')

    travel 25.hours do
      expect(conversation.reload.can_reply?).to be(false)
      Flows::RunJob.perform_now(conversation.id, 'wake', nil, session.id, session.reload.step_token)

      template = bot_messages.call.last
      expect(template.additional_attributes.dig('template_params', 'name')).to eq('order_update')
      Whatsapp::SendOnWhatsappService.new(message: template).perform
      expect(template.reload).to have_attributes(status: 'sent', source_id: 'wamid.1')
      expect(graph_calls.sole['type']).to eq('template')

      free_form = conversation.messages.create!(message_type: :outgoing, account: account, inbox: inbox, sender: bot, content: 'Plain text')
      Whatsapp::SendOnWhatsappService.new(message: free_form).perform
      expect(free_form.reload).to have_attributes(status: 'failed', external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
      expect(graph_calls.size).to eq(1)
    end
    expect(session.reload).to be_completed
  end

  it 'hands over instead of sending text when Send Message meets a closed window' do
    publish.call('nodes' => [node.call('start', 'start'), node.call('ask', 'question', 'text' => 'Your order number?', 'timeout_minutes' => 1440),
                             node.call('late', 'send_message', 'text' => 'Still there?'), node.call('end', 'end')],
                 'edges' => [edge.call('start', 'ask'), edge.call('ask', 'end', 'reply'), edge.call('ask', 'late', 'timeout'),
                             edge.call('late', 'end')])
    session = say.call('hi')

    travel 25.hours do
      Flows::RunJob.perform_now(conversation.id, 'wake', nil, session.id, session.reload.step_token)
    end

    expect(session.reload).to have_attributes(status: 'handed_off', context: include('end_reason' => 'window_closed'))
    expect(bot_messages.call.pluck(:content)).to eq(['Your order number?'])
  end

  {
    'deleted' => [->(list) { list.reject { |item| item['name'] == 'order_update' } }, 'template_not_found'],
    'no longer in that language' => [->(list) { list.map { |item| item.merge('language' => 'fr') } }, 'template_language_unavailable'],
    'disabled' => [->(list) { list.map { |item| item.merge('status' => 'DISABLED') } }, 'template_not_approved'],
    'paused' => [->(list) { list.map { |item| item.merge('status' => 'PAUSED') } }, 'template_not_approved'],
    'an authentication template' => [->(list) { list.map { |item| item.merge('category' => 'AUTHENTICATION') } }, 'template_not_allowed'],
    'with a location header' => [lambda { |list|
      list.map { |item| item.merge('components' => item['components'] + [{ 'type' => 'HEADER', 'format' => 'LOCATION' }]) }
    }, 'template_not_allowed']
  }.each do |change, (edit, code)|
    it "fails without sending anything when the template was #{change} after publishing" do
      straight.call(order_update)
      whatsapp.update_columns(message_templates: edit.call(whatsapp.message_templates)) # rubocop:disable Rails/SkipsModelValidations

      session = say.call('A-100')

      expect(session).to have_attributes(status: 'failed', failure_code: code)
      expect(conversation.reload).to be_open
      expect(bot_messages.call).to be_empty
    end
  end

  it 'fails when a value it needs is empty once the run fills it in (a variable without a value)' do
    straight.call(order_update.deep_merge('params' => { 'body' => { '3' => '{{flow.order.status}}' } }))

    expect(say.call('A-100')).to have_attributes(status: 'failed', failure_code: 'template_param_missing')
    expect(bot_messages.call).to be_empty
  end

  it 'follows failed when it is connected' do
    publish.call('nodes' => [node.call('start', 'start'), node.call('tpl', 'send_template', order_update), node.call('end', 'end'),
                             node.call('human', 'handoff', 'reason' => 'Template not sent')],
                 'edges' => [edge.call('start', 'tpl'), edge.call('tpl', 'end'), edge.call('tpl', 'human', 'failed')])
    whatsapp.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations

    expect(say.call('A-100')).to have_attributes(status: 'handed_off', context: include('end_reason' => 'handoff_node'))
    expect(conversation.messages.where(private: true).pluck(:content)).to eq(['Template not sent'])
  end

  describe 'a message the provider rejects' do
    it 'hands the waiting session to humans' do
      publish.call('nodes' => [node.call('start', 'start'), node.call('tpl', 'send_template', order_update),
                               node.call('ask', 'question', 'text' => 'Anything else?'), node.call('end', 'end')],
                   'edges' => [edge.call('start', 'tpl'), edge.call('tpl', 'ask'), edge.call('ask', 'end', 'reply')])
      session = say.call('A-100')
      template = bot_messages.call.first

      expect { template.update!(status: :failed, external_error: '(#132000) Number of parameters does not match') }
        .to have_enqueued_job(Flows::RunJob).with(conversation.id, 'rejected', template.id)
      Flows::RunJob.perform_now(conversation.id, 'rejected', template.id)

      expect(session.reload).to have_attributes(status: 'handed_off', context: include('end_reason' => 'message_rejected'))
      expect(conversation.reload).to be_open
    end

    it 'gives the conversation to humans when the session already completed' do
      straight.call(order_update)
      expect(say.call('A-100')).to be_completed
      template = bot_messages.call.sole

      expect { template.update!(status: :failed, external_error: '(#132000) Number of parameters does not match') }
        .to have_enqueued_job(Flows::RunJob).with(conversation.id, 'rejected', template.id)
      Flows::RunJob.perform_now(conversation.id, 'rejected', template.id)

      expect(conversation.reload).to be_open
    end

    it 'ignores failures of messages the flow did not send' do
      straight.call(order_update)
      say.call('A-100')
      agent_message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing)

      expect { agent_message.update!(status: :failed) }.not_to have_enqueued_job(Flows::RunJob).with(anything, 'rejected', anything)
    end
  end
end
