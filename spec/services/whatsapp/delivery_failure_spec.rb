require 'rails_helper'

# Meta error 131049 — "This message was not delivered to maintain healthy ecosystem engagement" — is a
# per-recipient marketing cap, proven recipient-level on live traffic: in the same minutes, on the same inbox,
# WABA, token and code path, two recipients reached delivered/read while two others failed this way. These
# examples pin that Lynomia treats it as exactly that and nothing more.
RSpec.describe Whatsapp::DeliveryFailure do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+96512345678') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '96512345678') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:wamid) { 'wamid.RESTRICTED1' }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, status: :sent, source_id: wamid, content: 'hi')
  end

  let(:restriction) do
    status_payload(131_049, 'This message was not delivered to maintain healthy ecosystem engagement.')
  end

  def status_payload(code, title)
    { object: 'whatsapp_business_account',
      entry: [{ id: '4584909965122758',
                changes: [{ field: 'messages',
                            value: { messaging_product: 'whatsapp',
                                     metadata: { display_phone_number: channel.phone_number.delete('+'),
                                                 phone_number_id: channel.provider_config['phone_number_id'] },
                                     statuses: [{ id: wamid, status: 'failed', timestamp: '1790716319',
                                                  recipient_id: '96512345678',
                                                  errors: [{ code: code, title: title }] }] } }] }] }
  end

  # 1. persisted as failed, with Meta's exact text
  describe 'persistence' do
    it 'records the message failed with Meta exact code and reason' do
      Webhooks::WhatsappEventsJob.new.perform(restriction.with_indifferent_access)

      expect(message.reload).to have_attributes(
        status: 'failed',
        external_error: '131049: This message was not delivered to maintain healthy ecosystem engagement.'
      )
    end
  end

  # 2. classified, with a stated retry policy
  describe 'classification' do
    it 'classifies 131049 as a recipient-scoped Meta delivery restriction that is never auto-retried' do
      failure = described_class.new('131049: This message was not delivered to maintain healthy ecosystem engagement.')

      expect(failure).to have_attributes(code: 131_049, classified?: true, recipient_scoped?: true,
                                         classification: described_class::RECIPIENT_DELIVERY_RESTRICTION,
                                         retry_policy: described_class::DO_NOT_AUTO_RETRY)
    end

    # 9a. 131042 is a different thing: the operator can fix billing, so the same message may later send.
    it 'keeps 131042 distinct, account-scoped and operator-retryable' do
      failure = described_class.new('131042: Business eligibility payment issue')

      expect(failure).to have_attributes(classification: described_class::BILLING_ELIGIBILITY,
                                         recipient_scoped?: false, retry_policy: described_class::DO_NOT_AUTO_RETRY)
    end

    # 9b. the local 24-hour refusal carries no Meta code at all, so it can never be read as one.
    it 'does not classify the local 24-hour window refusal' do
      failure = described_class.new(I18n.t('errors.whatsapp.message_outside_messaging_window'))

      expect(failure).to have_attributes(code: nil, classified?: false, recipient_scoped?: false,
                                         classification: described_class::UNCLASSIFIED,
                                         retry_policy: described_class::AUTO_RETRY_UNDEFINED)
    end

    # 9c. an OAuth failure is handled by a different mechanism entirely (code 190 -> reauthorization), and an
    # unobserved code must not be given a policy this repository cannot stand behind.
    it 'leaves an unobserved code unclassified rather than guessing' do
      expect(described_class.new('190: Invalid OAuth access token')).to have_attributes(
        classified?: false, recipient_scoped?: false, classification: described_class::UNCLASSIFIED
      )
    end

    it 'reads nothing from a blank or shapeless error' do
      expect(described_class.new(nil).code).to be_nil
      expect(described_class.new('no code here').code).to be_nil
    end
  end

  # 3, 4, 5, 6 — what it must NOT set in motion
  describe 'what a recipient restriction must not trigger' do
    it 'leaves the channel unlatched and its credentials untouched' do
      Webhooks::WhatsappEventsJob.new.perform(restriction.with_indifferent_access)

      expect(channel.reload).not_to be_reauthorization_required
      expect(channel.authorization_error_count).to eq(0)
      expect(channel.provider_config['api_key']).to eq('test_key')
    end

    it 'enqueues no re-send of its own' do
      expect { Webhooks::WhatsappEventsJob.new.perform(restriction.with_indifferent_access) }
        .not_to have_enqueued_job(SendReplyJob)
    end

    # Proven structurally rather than by a spy, because the point is that no such call exists on this path at all:
    # reauthorization is reserved for OAuth code 190 and webhook repair for a setup failure, and a delivery refusal
    # is neither. A later edit that reached for one of them would fail here.
    it 'has no reauthorization, webhook-repair or credential write anywhere on the status path' do
      source = ['app/services/whatsapp/incoming_message_base_service.rb',
                'app/services/messages/status_update_service.rb'].map { |file| Rails.root.join(file).read }.join

      expect(source).not_to match(/setup_webhooks|prompt_reauthorization|authorization_error|api_key/)
    end
  end

  # 7 + 8 — surfaced to the operator, and not repeatable against the same recipient
  describe 'the operator path' do
    before { Webhooks::WhatsappEventsJob.new.perform(restriction.with_indifferent_access) }

    it 'surfaces Meta reason on the message itself' do
      expect(message.reload.external_error).to include('131049')
    end

    it 'is recipient-scoped, so the retry endpoint refuses rather than re-sending' do
      expect(described_class.for(message.reload)).to be_recipient_scoped
    end

    it 'leaves an account-scoped failure retryable' do
      message.update!(status: :failed, external_error: '131042: Business eligibility payment issue')

      expect(described_class.for(message.reload)).not_to be_recipient_scoped
    end
  end
end
