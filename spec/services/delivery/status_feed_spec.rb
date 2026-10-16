require 'rails_helper'

# WHAT BECAME OF A MESSAGE, AND WHAT THIS SIDE MAY HONESTLY CLAIM ABOUT IT.
#
# The defect these exist for: `POST .../messages` answers 200 when the message ROW exists, and
# everything that decides whether it is actually sent -- the provider call, the platform
# workspace's UTILITY gate, the consent gate, the allowance meter -- runs afterwards. A partner
# reading that 200 as a send recorded "sent" for messages this side then refused.
RSpec.describe Delivery::StatusFeed do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, :with_phone_number, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '963900000001') }
  let(:conversation) do
    create(:conversation, contact_inbox: contact_inbox, contact: contact, inbox: channel.inbox, account: account)
  end

  def outgoing(**attrs)
    create(:message, conversation: conversation, account: account, inbox: channel.inbox,
                     message_type: :outgoing, **attrs)
  end

  describe 'the outcome it reports' do
    # `sent` is the column DEFAULT, written on INSERT before anything is attempted. Reporting
    # it as a send is the whole defect, so a row with no provider id is `queued`.
    it 'calls a row the provider has not answered for queued, not sent' do
      message = outgoing

      expect(message.status).to eq('sent')
      expect(described_class.outcome_of(message)).to eq(described_class::QUEUED)
    end

    # What distinguishes "we have it" from "the provider took it" is the provider's own id.
    it 'calls a row the provider gave an id for provider_accepted' do
      message = outgoing(source_id: 'wamid.HBg')

      expect(described_class.outcome_of(message)).to eq(described_class::PROVIDER_ACCEPTED)
    end

    it 'reports a confirmed delivery and a read separately' do
      expect(described_class.outcome_of(outgoing(status: :delivered))).to eq(described_class::DELIVERED)
      expect(described_class.outcome_of(outgoing(status: :read))).to eq(described_class::READ)
    end

    # THE DISTINCTION A PARTNER CANNOT MAKE FROM `failed` ALONE, and the reason the outcome
    # vocabulary is not Lynomia's enum: a provider failure may be worth retrying and a policy
    # refusal never is.
    it 'tells a policy refusal apart from a provider failure' do
      refused = outgoing(status: :failed,
                         content_attributes: { external_error: I18n.t('errors.whatsapp.consent.consent_withdrawn') })
      broke = outgoing(status: :failed, content_attributes: { external_error: '131026: Message undeliverable' })

      expect(described_class.outcome_of(refused)).to eq(described_class::REFUSED)
      expect(described_class.reason_code(refused)).to eq('consent_withdrawn')

      expect(described_class.outcome_of(broke)).to eq(described_class::FAILED)
      expect(described_class.reason_code(broke)).to eq('131026')
    end

    it 'names every eligibility gate this installation has' do
      described_class::ELIGIBILITY_REASONS.each do |reason|
        message = outgoing(status: :failed,
                           content_attributes: { external_error: I18n.t("errors.whatsapp.consent.#{reason}") })

        expect(described_class.outcome_of(message)).to eq(described_class::REFUSED)
        expect(described_class.reason_code(message)).to eq(reason)
      end
    end
  end

  describe 'publishing' do
    let!(:webhook) do
      create(:webhook, account: account, url: 'https://storesyria.test/lynomia/platform-events',
                       subscriptions: [described_class::EVENT])
    end

    it 'is sent when the status changes, and not when anything else does' do
      message = outgoing

      expect { message.update!(content: 'edited') }.not_to have_enqueued_job(WebhookJob)
      expect { message.update!(status: :delivered) }.to have_enqueued_job(WebhookJob)
    end

    # The gates write the row directly rather than through Messages::StatusUpdateService, so a
    # hook on that service would have missed exactly the refusals this feed exists to report.
    it 'is sent for a refusal written straight onto the row' do
      message = outgoing

      expect do
        message.update!(status: :failed,
                        content_attributes: { external_error: I18n.t('errors.whatsapp.consent.consent_withdrawn') })
      end.to have_enqueued_job(WebhookJob)
    end

    it 'says nothing to a workspace that did not subscribe' do
      webhook.update!(subscriptions: ['conversation_created'])
      message = outgoing

      expect { message.update!(status: :delivered) }.not_to have_enqueued_job(WebhookJob)
    end

    it 'says nothing about an incoming message' do
      incoming = create(:message, conversation: conversation, account: account, inbox: channel.inbox,
                                  message_type: :incoming)

      expect { incoming.update!(status: :delivered) }.not_to have_enqueued_job(WebhookJob)
    end
  end

  describe 'the ordering key' do
    # A late receipt must not overwrite a newer one at the receiver, and the receiver cannot
    # decide that without something to compare. Microseconds, as an integer, because comparing
    # formatted timestamps across two languages' parsers is how that goes wrong.
    it 'is an integer microsecond stamp that moves forward with the row' do
      message = outgoing
      first = described_class.payload(message)[:occurred_at_us]

      travel_to(2.seconds.from_now) { message.update!(status: :delivered) }

      expect(described_class.payload(message.reload)[:occurred_at_us]).to be > first
      expect(first).to be_a(Integer)
    end

    # A republication of the same transition must be a no-op at a receiver that dedupes, which
    # is why the id is derived rather than random -- the same rule Consents::ChangeFeed follows.
    it 'derives a delivery id that repeats for the same transition' do
      message = outgoing
      ids = Array.new(2) { "delivery-#{message.id}-#{described_class.occurred_at_us(message)}" }

      expect(ids.uniq.size).to eq(1)
    end
  end

  describe 'what the payload carries' do
    it 'names the account, the message and both vocabularies' do
      message = outgoing(source_id: 'wamid.HBg', status: :delivered)

      payload = described_class.payload(message)

      expect(payload).to include(
        event: described_class::EVENT,
        account: { id: account.id },
        status: 'delivered',
        outcome: described_class::DELIVERED
      )
      expect(payload[:message]).to include(id: message.id, source_id: 'wamid.HBg',
                                           conversation_id: conversation.display_id)
    end

    # The receiver checks it: a signature proves who sent a delivery, the account proves what
    # it is allowed to talk about.
    it 'carries no message body, recipient or token' do
      message = outgoing(content: 'Your integration is broken', source_id: 'wamid.HBg')

      serialised = described_class.payload(message).to_json

      expect(serialised).not_to include('Your integration is broken')
      expect(serialised).not_to include(contact.phone_number.to_s)
    end
  end
end
