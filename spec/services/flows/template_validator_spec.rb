require 'rails_helper'

# The publish gate for Send template nodes (docs/flow-builder/04-node-contracts.md §send template): the template is looked
# up in this account's WhatsApp inboxes only, and every value it takes must be set.
RSpec.describe Flows::TemplateValidator do
  let(:offer) do
    { 'name' => 'spring_offer', 'language' => 'en_US', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Hi {{1}}, {{2}} off today.' },
                       { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'example' => 'SPRING' }] }] }
  end
  let(:account) { create(:account) }
  let(:inbox) { whatsapp_inbox.call(account, [offer]) }
  let(:whatsapp_inbox) do
    lambda do |owner, templates|
      create(:channel_whatsapp, provider: 'whatsapp_cloud', account: owner, validate_provider_config: false, sync_templates: false,
                                message_templates: templates).inbox
    end
  end
  let(:valid) do
    { 'name' => 'spring_offer', 'language' => 'en_US',
      'params' => { 'header' => { 'media_url' => 'https://cdn.example.com/spring.jpg', 'media_type' => 'image' },
                    'body' => { '1' => '{{contact.first_name}}', '2' => '20%' },
                    'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'SPRING20' }] } }
  end
  let(:errors) { ->(data, inboxes = []) { described_class.new(account, data, inboxes).errors } }

  it 'accepts an approved template of a connected inbox with every value set' do
    expect(errors.call(valid, [inbox])).to eq([])
  end

  it 'accepts a flow not connected yet when one of the account WhatsApp inboxes has the template' do
    inbox
    whatsapp_inbox.call(account, [])

    expect(errors.call(valid)).to eq([])
  end

  it "never finds another account's template" do
    whatsapp_inbox.call(create(:account), [offer])
    own = whatsapp_inbox.call(account, [])

    expect(errors.call(valid)).to eq([['template_not_found', own.name]])
    expect(errors.call(valid, [own])).to eq([['template_not_found', own.name]])
  end

  it 'needs the template on every connected inbox' do
    other = whatsapp_inbox.call(account, [offer.merge('language' => 'ar')])

    expect(errors.call(valid, [inbox, other])).to eq([['template_language_unavailable', other.name]])
  end

  it 'refuses templates the composer would not send and channels without templates' do
    rejected = whatsapp_inbox.call(account, [offer.merge('status' => 'REJECTED')])
    authentication = whatsapp_inbox.call(account, [offer.merge('category' => 'AUTHENTICATION')])
    expect(errors.call(valid, [rejected])).to eq([['template_not_approved', rejected.name]])
    expect(errors.call(valid, [authentication])).to eq([['template_not_allowed', authentication.name]])
    expect(errors.call(valid, [create(:inbox, account: account)])).to eq([['template_no_inbox']])
    expect(errors.call(valid.except('language'), [inbox])).to eq([['template_required']])
  end

  it 'finds every value left empty before publishing' do
    data = valid.merge('params' => { 'header' => { 'media_url' => '' }, 'body' => { '1' => 'Omar', '2' => ' ' } })

    expect(errors.call(data, [inbox])).to contain_exactly(['template_param_missing', 'header.media_url'], ['template_param_missing', 'body.2'],
                                                          ['template_param_missing', 'buttons.0'])
  end

  it 'checks each value: allow-listed variables, a fixed http(s) media link, a short copy code of flow values only' do
    data = valid.deep_merge('params' => { 'header' => { 'media_url' => 'javascript:alert(1)' }, 'body' => { '2' => '{{ contact.password }}' } })
    data['params']['buttons'] = [{ 'type' => 'copy_code', 'parameter' => 'SPRING-2026-EXTRA' }]
    expect(errors.call(data, [inbox])).to contain_exactly(['invalid_media_url', 'header.media_url'], ['unknown_variable', 'contact.password'],
                                                          ['copy_code_too_long', 15])

    data['params']['buttons'] = [{ 'type' => 'copy_code', 'parameter' => '{{contact.name}}' }]
    data['params']['header']['media_url'] = 'https://cdn.example.com/{{flow.reply}}.jpg'
    expect(errors.call(data, [inbox])).to include(['unknown_variable', 'contact.name'], ['invalid_media_url', 'header.media_url'])
    expect(errors.call(valid.merge('params' => 'body'), [inbox])).to eq([['invalid_template_params']])
  end

  it 'is the graph validator check for send_template nodes, against the inboxes the flow is connected to' do
    node = { 'id' => 'tpl', 'type' => 'send_template', 'position' => { 'x' => 0, 'y' => 0 }, 'data' => valid.merge('language' => 'fr') }
    graph = { 'nodes' => [node.merge('id' => 's', 'type' => 'start', 'data' => {}), node, node.merge('id' => 'e', 'type' => 'end', 'data' => {})],
              'edges' => [{ 'id' => 's-next', 'source' => 's', 'sourceHandle' => 'next', 'target' => 'tpl' },
                          { 'id' => 'tpl-next', 'source' => 'tpl', 'sourceHandle' => 'next', 'target' => 'e' }] }

    expect(Flows::GraphValidator.new(account, graph, inboxes: [inbox]).errors)
      .to eq([{ code: 'template_language_unavailable', node_id: 'tpl', detail: inbox.name }])
  end
end
