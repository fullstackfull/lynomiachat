require 'rails_helper'

# An answer to a WhatsApp interactive message keeps the chosen button / row id next to its title, so a flow routes by the
# option it sent (docs/flow-builder/06-whatsapp-channel-capabilities.md).
RSpec.describe Whatsapp::IncomingMessageWhatsappCloudService do
  let(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:payload) do
    lambda do |key, interactive|
      message = { from: '966500000003', to: '966500000003', id: "wamid.#{SecureRandom.hex(4)}", timestamp: '1664799904', type: 'interactive',
                  interactive: interactive }
      value = { contacts: [{ profile: { name: 'Sara' }, wa_id: '966500000003' }] }.merge(key => [message])
      { phone_number: whatsapp_channel.phone_number, object: 'whatsapp_business_account', entry: [{ changes: [{ value: value }] }] }
        .with_indifferent_access
    end
  end

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  it 'stores the id of the chosen button and list row' do
    button = payload.call(:messages, { type: 'button_reply', button_reply: { id: 'lfb:menu:care', title: 'Care' } })
    row = payload.call(:messages, { type: 'list_reply', list_reply: { id: 'lfb:list:vip', title: 'VIP' } })
    [button, row].each { |params| described_class.new(inbox: whatsapp_channel.inbox, params: params).perform }

    replies = whatsapp_channel.inbox.messages.order(:id).map { |message| [message.content, message.content_attributes['interactive_reply']] }
    expect(replies).to eq([['Care', { 'type' => 'button_reply', 'id' => 'lfb:menu:care', 'title' => 'Care' }],
                           ['VIP', { 'type' => 'list_reply', 'id' => 'lfb:list:vip', 'title' => 'VIP' }]])
  end

  it 'does not mark the business own echoes as customer choices' do
    answer = payload.call(:messages, { type: 'button_reply', button_reply: { id: 'a', title: 'A' } })
    described_class.new(inbox: whatsapp_channel.inbox, params: answer).perform
    echo = payload.call(:message_echoes, { type: 'button_reply', button_reply: { id: 'b', title: 'B' } })
    echo[:entry][0][:changes][0][:value][:message_echoes][0][:from] = whatsapp_channel.phone_number.delete('+')
    described_class.new(inbox: whatsapp_channel.inbox, params: echo, outgoing_echo: true).perform

    expect(whatsapp_channel.inbox.messages.outgoing.last.content_attributes).not_to have_key('interactive_reply')
  end
end
