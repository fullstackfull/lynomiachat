require 'rails_helper'

# Package E's router (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §4.7), driven
# through the service that owns the status path rather than called on its own. The property under test is a
# pair: upstream still handles a report for a conversation message exactly as it did, and this handles every
# report upstream abandons for want of a `Message` -- which is every report for a campaign send, because a
# campaign send creates none. Calling the router directly would prove the lookup and nothing about the pair.
RSpec.describe Whatsapp::DeliveryReport do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+96512345678') }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago) }
  # Meta's own timestamp for the event, in unix seconds, as it arrives: a string.
  let(:reported_at) { '1790716319' }
  # An error entry as a `failed` report carries it: a numeric code, a short title, and the sentence about this
  # particular send under error_data.
  let(:meta_error) do
    { code: 131_047, title: 'Re-engagement message', message: 'Re-engagement message',
      error_data: { details: 'Message failed to send because more than 24 hours have passed since the customer last replied.' } }
  end

  # The record the whole package exists for: a campaign send, dispatched with no conversation and no Message,
  # holding the identifier the send call returned.
  let!(:recipient) do
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: contact,
                              status: :sent, source_id: 'wamid.CAMPAIGN1', sent_at: 10.minutes.ago)
  end

  # Meta's `value` object -- what the service is handed once the job has dug it out of entry/changes
  # (app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:8), with indifferent access because
  # `params.to_unsafe_hash` is the shape the job carries. `to:` is the inbox the webhook was already routed
  # to, which is the whole reason a tenant-scoped lookup is possible at this point.
  def deliver(*reports, to: inbox)
    payload = { messaging_product: 'whatsapp',
                metadata: { display_phone_number: channel.phone_number.delete('+'),
                            phone_number_id: channel.provider_config['phone_number_id'] },
                statuses: reports }.with_indifferent_access
    Whatsapp::IncomingMessageBaseService.new(inbox: to, params: payload).perform
  end

  def report(source_id, state, extra = {})
    { id: source_id, status: state, timestamp: reported_at, recipient_id: '96512345678' }.merge(extra)
  end

  # E-1
  context 'when the identifier belongs to a conversation message' do
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '96512345678') }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    end
    let!(:message) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :sent, source_id: 'wamid.REPLY1', content: 'hi')
    end

    it 'advances the message and leaves every campaign recipient alone' do
      before_recipient = recipient.reload.attributes

      deliver(report('wamid.REPLY1', 'delivered'))

      expect(message.reload.status).to eq('delivered')
      # Byte-identical, updated_at included. The recipient path runs on every statuses payload now, so any
      # write here would mean the two paths both believe they own this identifier.
      expect(recipient.reload.attributes).to eq(before_recipient)
    end
  end

  # E-2 delivered the way Meta delivers it: the whole envelope the controller enqueues, with the channel -- and
  # so the inbox the lookup is scoped to -- resolved from the payload's own metadata. Statuses arrive on the
  # `messages` subscription, which is why the field says so. This is what pins the shape that every other
  # example here abbreviates to the `value` object the job hands on.
  it 'advances the recipient when the report arrives as the webhook envelope Meta posts' do
    envelope = { object: 'whatsapp_business_account',
                 entry: [{ id: '4584909965122758',
                           changes: [{ field: 'messages',
                                       value: { messaging_product: 'whatsapp',
                                                metadata: { display_phone_number: channel.phone_number.delete('+'),
                                                            phone_number_id: channel.provider_config['phone_number_id'] },
                                                statuses: [report(recipient.source_id, 'delivered')] } }] }] }

    Webhooks::WhatsappEventsJob.new.perform(envelope.with_indifferent_access)

    expect(recipient.reload).to have_attributes(status: 'delivered', delivered_at: Time.zone.at(reported_at.to_i))
  end

  # E-2, and the first half of E-10
  it 'advances a campaign recipient that has no conversation message, and creates nothing on the way' do
    expect { deliver(report(recipient.source_id, 'delivered')) }
      .not_to(change { [Contact.count, ContactInbox.count, Conversation.count, Message.count] })

    # Meta's own timestamp, not the time the report happened to be processed: the recipient list reads these
    # columns as the log of what the provider reported.
    expect(recipient.reload).to have_attributes(status: 'delivered', delivered_at: Time.zone.at(reported_at.to_i))
  end

  # E-3. Meta retries any delivery that does not return success, so turning a harmless report into a failure
  # buys a retry storm. Reports for messages sent from other systems on the same number, for messages that
  # predate the installation, and for messages whose records were deleted all land here.
  it 'writes nothing and logs no error for an identifier no record carries' do
    allow(Rails.logger).to receive(:error)
    expect(ChatwootExceptionTracker).not_to receive(:new)
    before_recipient = recipient.reload.attributes

    expect { deliver(report('wamid.NOBODY-OWNS-THIS', 'delivered')) }.not_to raise_error

    expect(recipient.reload.attributes).to eq(before_recipient)
    expect(Rails.logger).not_to have_received(:error)
  end

  # E-4
  it 'applies all three entries of a payload that carries three' do
    read, failed = Array.new(2) do |index|
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox,
                                contact: create(:contact, account: account), status: :sent,
                                source_id: "wamid.CAMPAIGN#{index + 2}", sent_at: 10.minutes.ago)
    end

    deliver(report(recipient.source_id, 'delivered'),
            report(read.source_id, 'read'),
            report(failed.source_id, 'failed', errors: [meta_error]))

    expect(recipient.reload.status).to eq('delivered')
    expect(read.reload.status).to eq('read')
    # Three columns, not one joined string: the recipient list shows the code and the reason separately
    # (package D §3), and `title` is the human part of a report error while `error_data.details` is the
    # sentence about this one send -- the reverse of a send response, where `message` is the human part.
    expect(failed.reload).to have_attributes(
      status: 'failed', error_code: '131047', error_title: 'Re-engagement message',
      error_message: 'Message failed to send because more than 24 hours have passed since the customer last replied.'
    )
  end

  # E-5. `deleted` is outside the four states the product records, which is the point of the example: Meta has
  # put more than four values on this field and will put more there again, and a state stored on the record
  # that no reader of the record can interpret is worse than one that was ignored.
  it 'applies the states it knows, ignores one it does not, and stores no unknown state' do
    unknown = CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox,
                                        contact: create(:contact, account: account), status: :sent,
                                        source_id: 'wamid.CAMPAIGN2', sent_at: 10.minutes.ago)
    before_unknown = unknown.reload.attributes

    expect { deliver(report(recipient.source_id, 'delivered'), report(unknown.source_id, 'deleted')) }.not_to raise_error

    expect(recipient.reload.status).to eq('delivered')
    expect(unknown.reload.attributes).to eq(before_unknown)
  end

  # E-6
  it 'leaves the record identical when Meta redelivers the same payload' do
    deliver(report(recipient.source_id, 'delivered'))
    after_first_delivery = recipient.reload.attributes

    deliver(report(recipient.source_id, 'delivered'))

    # updated_at included: the second application has to write nothing at all, not rewrite the same values.
    expect(recipient.reload.attributes).to eq(after_first_delivery)
  end

  # E-7 [isolation]. The identifier in a report is attacker-supplied input on a public endpoint. Meta's
  # signature is the real protection and is verified long before this point, but the lookup is still narrowed
  # to the inbox the webhook was routed to, so a report delivered for one account cannot reach another's row.
  it 'cannot advance an account recipient through another account inbox' do
    other_inbox = create(:channel_whatsapp, account: create(:account), provider: 'whatsapp_cloud',
                                            sync_templates: false, validate_provider_config: false).inbox
    before_recipient = recipient.reload.attributes

    deliver(report(recipient.source_id, 'delivered'), to: other_inbox)

    expect(recipient.reload.attributes).to eq(before_recipient)
  end

  # E-9. A number connected through Meta Embedded Signup coexistence is the same official Cloud API channel
  # with the same webhook shape, so this is E-2 again -- asserted because the requirement is that there is no
  # second code path for it, and an assertion is the only way to show that the first one serves it.
  context 'when the number is connected through business-app coexistence' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                provider_config: { 'is_coexistence' => true }, sync_templates: false,
                                validate_provider_config: false)
    end

    it 'advances the recipient exactly as an ordinary cloud number does' do
      expect(channel.provider_config['is_coexistence']).to be(true)

      expect { deliver(report(recipient.source_id, 'delivered')) }
        .not_to(change { [Contact.count, ContactInbox.count, Conversation.count, Message.count] })

      expect(recipient.reload).to have_attributes(status: 'delivered', delivered_at: Time.zone.at(reported_at.to_i))
    end
  end

  # E-10. Message ingestion does not run for a statuses payload at all, so there is nothing for a report to
  # invent a contact or a conversation from -- including when the report is the one that ends the ladder.
  it 'creates no contact, conversation or message for any state it applies' do
    expect do
      deliver(report(recipient.source_id, 'sent'),
              report(recipient.source_id, 'delivered'),
              report(recipient.source_id, 'read'))
    end.not_to(change { [Contact.count, ContactInbox.count, Conversation.count, Message.count] })

    expect(recipient.reload.status).to eq('read')
  end

  # E-12
  describe 'a payload the product cannot read' do
    it 'raises nothing and advances nothing for a missing identifier or a missing state' do
      before_recipient = recipient.reload.attributes

      [{ status: 'delivered', timestamp: reported_at },
       { id: recipient.source_id, timestamp: reported_at, recipient_id: '96512345678' }].each do |entry|
        expect { deliver(entry) }.not_to raise_error

        expect(recipient.reload.attributes).to eq(before_recipient)
      end
    end

    # Meta posts more than delivery reports to the same callback, and a template-status update carries no
    # `statuses` key at all -- so this is a payload that is not of the expected shape in the first place.
    it 'raises nothing and advances nothing for a payload that is not a delivery report' do
      payload = { field: 'message_template_status_update',
                  value: { event: 'APPROVED', message_template_id: 1_234, message_template_name: 'ticket_status_updated' } }
      before_recipient = recipient.reload.attributes

      expect { Whatsapp::IncomingMessageBaseService.new(inbox: inbox, params: payload.with_indifferent_access).perform }
        .not_to raise_error

      expect(recipient.reload.attributes).to eq(before_recipient)
      expect(Message.count).to eq(0)
    end

    # Each entry is contained on its own. Meta redelivers anything that does not return success, so one entry
    # that cannot be read must not take the rest of the payload down with it into a retry loop.
    it 'still applies the readable entry of a payload whose other entry is not an object at all' do
      allow(Rails.logger).to receive(:error)

      expect { deliver(report(recipient.source_id, 'delivered'), 'wamid.NOT-AN-ENTRY') }.not_to raise_error

      expect(recipient.reload.status).to eq('delivered')
      # Reported, unlike the report that simply matches nothing above: an entry the product cannot read at all
      # means the product is reading Meta wrongly, and the only view an operator has of that is the report.
      expect(Rails.logger).to have_received(:error).at_least(:once)
    end
  end
end
