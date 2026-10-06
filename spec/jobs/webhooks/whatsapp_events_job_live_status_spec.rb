require 'rails_helper'

# The delivery-status payload Meta actually sent to a live Lynomia installation, captured from that server's
# journal: a `statuses` entry with status=failed and error 131042, alongside Coexistence identity fields
# (`recipient_user_id` on the status, `user_id` on the contact). Kept verbatim apart from nothing.
#
# It exists because a live diagnosis found thirteen outbound messages sitting at `sent` with no delivery status,
# and "did we lose the status, or did it never arrive" could not be answered from that server alone. It never
# arrived: a stale phone-level callback override pointed the number at a host whose nginx answered 502 before
# Rails saw anything. This pins the half we own — given the payload, the status is applied and Meta's reason kept.
RSpec.describe Webhooks::WhatsappEventsJob do
  describe 'Meta delivery-status ingestion on a real captured payload' do
    let(:phone_number_id) { '1357821967407914' }
    let(:waba_id) { '4584909965122758' }
    let(:account) { create(:account) }
    let(:channel) do
      create(:channel_whatsapp, account: account, phone_number: '+96597852210', provider: 'whatsapp_cloud',
                                sync_templates: false, validate_provider_config: false)
    end
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: account, phone_number: '+96597945452') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '96597945452') }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    end
    let(:wamid) { 'wamid.HBgLOTY1OTc5NDU0NTIVAgARGBI2MDE4MDEwQUNFM0QxMzI3NUUA' }
    let!(:message) do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, status: :sent, source_id: wamid, content: 'hi')
    end
    let(:payload) do
      {
        object: 'whatsapp_business_account',
        entry: [{
          id: waba_id,
          changes: [{
            field: 'messages',
            value: {
              messaging_product: 'whatsapp',
              metadata: { display_phone_number: '96597852210', phone_number_id: phone_number_id },
              contacts: [{ wa_id: '96597945452', user_id: 'KW.1839269920588199' }],
              statuses: [{
                id: wamid, status: 'failed', timestamp: '1790716319',
                recipient_id: '96597945452', recipient_user_id: 'KW.1839269920588199',
                errors: [{ code: 131_042, title: 'Business eligibility payment issue',
                           message: 'Business eligibility payment issue',
                           error_data: { details: 'your WhatsApp Business account currency is not configured.' },
                           href: 'https://business.facebook.com/billing_hub/accounts/details/' }]
              }]
            }
          }]
        }]
      }
    end

    # The factory writes its own provider_config, and Whatsapp::WebhookChannelFinderService accepts a candidate
    # only when the stored phone_number_id equals the one in the payload metadata — so the real id has to be on
    # the row for this to exercise anything. Getting this wrong is what made the first attempt at this spec look
    # like a product defect.
    before do
      channel.provider_config = channel.provider_config.merge('phone_number_id' => phone_number_id,
                                                              'business_account_id' => waba_id)
      channel.save!
    end

    it 'applies the failed status and preserves Meta error 131042' do
      described_class.new.perform(payload.with_indifferent_access)

      expect(message.reload).to have_attributes(status: 'failed',
                                                external_error: '131042: Business eligibility payment issue')
    end

    # What the worker is actually handed: ActiveJob serialises the arguments and Sidekiq hands back a JSON round
    # trip. If indifferent access did not survive that boundary, every key lookup in the status path would miss
    # silently and the message would sit at `sent` with nothing logged.
    it 'applies the status after the ActiveJob JSON round trip Sidekiq performs' do
      described_class.new.perform(JSON.parse(payload.to_json).with_indifferent_access)

      expect(message.reload.status).to eq('failed')
    end

    # The one drop that must stay loud: a payload naming a phone_number_id this installation does not own is
    # refused, and says so at error level rather than vanishing into a warning.
    it 'refuses a payload whose phone_number_id this installation does not own, and says so' do
      foreign = payload.deep_dup
      foreign[:entry][0][:changes][0][:value][:metadata][:phone_number_id] = '9999999999999'
      allow(Rails.logger).to receive(:error)

      described_class.new.perform(foreign.with_indifferent_access)

      expect(Rails.logger).to have_received(:error).with(/\[WHATSAPP INGEST\] event=unroutable_payload/)
      expect(message.reload.status).to eq('sent')
    end
  end
end
