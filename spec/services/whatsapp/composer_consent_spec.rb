require 'rails_helper'

# THE COMPOSER ASKS WHAT THE PERSON AGREED TO (B3.1).
#
# Every other outbound template path in this system asks: the campaign senders through
# Campaigns::SendGuard, the automation template action and the flow Send-template node through
# Commerce::MessagingEligibility. The two composer paths -- replying in a conversation, and
# opening a new one -- did not, and because a template send deliberately skips the 24-hour
# window there was nothing else in the way either. An agent could send an approved MARKETING
# template to somebody who had replied STOP.
#
# The gate sits in Whatsapp::SendOnWhatsappService because that is what every message-borne
# template actually reaches. Messages::MessageBuilder looks like the shared entry point and is
# not: Flows::Run#say creates the message directly and would route around it.
RSpec.describe 'sending a WhatsApp template from the composer', type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates)
  end
  let(:templates) do
    [{ 'name' => 'autumn_sale', 'language' => 'en_US', 'status' => 'approved', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Sale!' }] },
     { 'name' => 'order_shipped', 'language' => 'en_US', 'status' => 'approved', 'category' => 'UTILITY',
       'components' => [{ 'type' => 'BODY', 'text' => 'On its way.' }] }]
  end
  let(:contact) { create(:contact, :with_phone_number, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '963900000000') }
  let(:conversation) do
    create(:conversation, contact_inbox: contact_inbox, contact: contact, inbox: channel.inbox, account: account)
  end

  def send_template(name)
    message = create(:message, conversation: conversation, account: account, message_type: :outgoing,
                               additional_attributes: { 'template_params' => { 'name' => name, 'language' => 'en_US',
                                                                               'processed_params' => { 'body' => {} } } })
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  def record(state, purpose)
    Commerce::MessagingConsents.record(
      account: account, contact: contact,
      decision: Commerce::MessagingConsents::Decision.new(state: state, source: 'merchant', purposes: [purpose.to_s])
    )
  end

  before { allow(channel).to receive(:send_template).and_return('wamid.sent') }

  # The gate is prepended onto the OSS service, so the behaviour is asserted through the real
  # class rather than through the module in isolation.
  it 'is prepended onto the service the composer reaches' do
    expect(Whatsapp::SendOnWhatsappService.ancestors).to include(Custom::Whatsapp::SendOnWhatsappService)
  end

  context 'when the account runs the commerce consent subsystem' do
    before { account.enable_features('lynomia_commerce') }

    it 'refuses a marketing template to somebody who never opted in' do
      message = send_template('autumn_sale')

      expect(message.status).to eq('failed')
      expect(message.external_error).to include('has not opted in to marketing')
    end

    it 'sends a marketing template to somebody who did opt in' do
      record(:granted, :promotional)

      expect(send_template('autumn_sale').status).not_to eq('failed')
    end

    # A utility template is the service the person asked for. Withholding it for want of a
    # marketing opt-in is a worse outcome for them than receiving it.
    it 'sends a utility template with no marketing opt-in at all' do
      expect(send_template('order_shipped').status).not_to eq('failed')
    end
  end

  context 'when the account does not run it' do
    # The strict question cannot be asked here: MessagingEligibility refuses a promotional send
    # unless a grant EXISTS, and this account has no merchant-facing way to record one. Asking
    # it would refuse every marketing template in the product rather than close a hole.
    it 'sends a marketing template, because nobody has decided otherwise' do
      expect(send_template('autumn_sale').status).not_to eq('failed')
    end

    # ...but a decision somebody actually made still stops it, in any account. STOP is matched
    # on the inbound message by a listener that is registered unconditionally, so this is the
    # case that exists everywhere.
    it 'refuses once the person has replied STOP' do
      record(:withdrawn, :promotional)

      message = send_template('autumn_sale')

      expect(message.status).to eq('failed')
      expect(message.external_error).to include('asked not to be messaged')
    end

    it 'refuses a utility template too once they have withdrawn' do
      record(:withdrawn, :transactional)

      expect(send_template('order_shipped').status).to eq('failed')
    end

    it 'refuses when the provider says the number cannot receive' do
      record(:suppressed, :promotional)

      expect(send_template('autumn_sale').external_error).to include('cannot receive')
    end
  end

  it 'refuses anything at all to a blocked contact' do
    contact.update!(blocked: true)

    expect(send_template('order_shipped').external_error).to include('blocked')
  end
end
