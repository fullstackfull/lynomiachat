require 'rails_helper'

# THE CHECK THAT ONLY EARNS ITS PLACE BECAUSE TIME HAS PASSED.
#
# Campaigns::Eligibility already filters the audience when it is resolved. This is asked again
# per recipient, immediately before the provider call, and the difference between them is the
# whole point: a campaign is dispatched by a five-minute scheduler and then iterates its
# entire audience in one job. Between the audience being resolved and a given recipient being
# reached, the shopper can reply STOP, an agent can block them, the provider can report the
# number dead, an operator can revoke the integration or throw the kill switch.
#
# EVERY EXAMPLE HERE THEREFORE CHANGES STATE AFTER THE AUDIENCE IS FIXED, by holding the
# resolved relation still and then making the change. A test that set the state up front would
# pass against an implementation that only filtered at resolution time, and would prove
# nothing about the boundary.
RSpec.describe Campaigns::SendGuard do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:shopper) { create(:contact, :with_phone_number, account: account, name: 'Shopper') }
  let(:resolved) { [shopper] }

  def stop(contact)
    Commerce::MessagingConsents.record(
      account: account, contact: contact,
      decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
    )
  end

  # --------------------------------------------------------------- WhatsApp
  context 'with the WhatsApp sender' do
    let!(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
    end
    let(:campaign) do
      create(:campaign, inbox: channel.inbox, account: account, campaign_type: :one_off,
                        template_params: { 'name' => 't', 'category' => 'UTILITY', 'language' => 'en',
                                           'processed_params' => { 'body' => {} } })
    end

    before do
      account.enable_features!(:whatsapp_campaign)
      stub_request(:post, /graph\.facebook\.com.*messages/)
        .to_return(status: 200, body: { messages: [{ id: 'm1' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(channel) # rubocop:disable RSpec/AnyInstance
      allow(campaign).to receive(:audience_contacts).and_return(resolved)
    end

    it 'does not send to someone who opted out after the audience was resolved' do
      expect(channel).not_to receive(:send_template)
      stop(shopper)

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
    end

    # The analytics breakdown had no word for a consent skip, so a campaign that correctly
    # refused looked exactly like one where consent was never checked.
    it 'records why, in the closed vocabulary the skip breakdown groups on' do
      stop(shopper)

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      recipient = campaign.campaign_recipients.sole
      expect(recipient.status).to eq('skipped')
      expect(recipient.error_message).to eq(Campaigns::RecipientSnapshot::CONSENT_REASONS[:consent_withdrawn])
      expect(Campaigns::RecipientSnapshot::SKIP_REASONS).to include(recipient.error_message)
    end

    it 'stops mid-run when the kill switch is thrown' do
      expect(channel).not_to receive(:send_template)
      account.update!(settings: account.settings.merge('campaign_sending_halted' => true))

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(campaign.campaign_recipients.sole.error_message)
        .to eq(Campaigns::RecipientSnapshot::CONSENT_REASONS[:outbound_halted])
    end

    it 'stops when a partner installation is revoked after the audience was resolved' do
      store = create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1')
      campaign.update!(commerce_store: store)
      expect(channel).not_to receive(:send_template)
      store.update!(status: :disconnected)

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(campaign.campaign_recipients.sole.error_message)
        .to eq(Campaigns::RecipientSnapshot::CONSENT_REASONS[:installation_revoked])
    end
  end

  # --------------------------------------------------------------- both SMS senders
  # Verified separately rather than assumed from the WhatsApp result: they are different
  # files with their own loops, and a guard added to one proves nothing about the other.
  context 'with the SMS senders' do
    let!(:sms_channel) { create(:channel_sms, account: account) }
    let!(:twilio_channel) { create(:channel_twilio_sms, account: account) }
    let(:twilio_client) { double }
    let(:twilio_messages) { double }

    def granted(contact)
      Commerce::MessagingConsents.record(
        account: account, contact: contact,
        decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant',
                                                            purposes: ['promotional'])
      )
    end

    it 'does not send when the Bandwidth recipient opted out after resolution' do
      campaign = create(:campaign, inbox: sms_channel.inbox, account: account, campaign_type: :one_off)
      granted(shopper)
      allow(campaign).to receive(:audience_contacts).and_return(resolved)
      allow_any_instance_of(Sms::OneoffSmsCampaignService).to receive(:channel).and_return(sms_channel) # rubocop:disable RSpec/AnyInstance

      expect(sms_channel).not_to receive(:send_text_message)
      stop(shopper)

      Sms::OneoffSmsCampaignService.new(campaign: campaign).perform
    end

    it 'does not send when the Twilio recipient opted out after resolution' do
      campaign = create(:campaign, inbox: twilio_channel.inbox, account: account, campaign_type: :one_off)
      granted(shopper)
      allow(campaign).to receive(:audience_contacts).and_return(resolved)
      allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
      allow(twilio_client).to receive(:messages).and_return(twilio_messages)

      expect(twilio_channel).not_to receive(:send_message)
      stop(shopper)

      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform
    end

    it 'halts both SMS senders on the kill switch' do
      account.update!(settings: account.settings.merge('campaign_sending_halted' => true))
      granted(shopper)
      sms = create(:campaign, inbox: sms_channel.inbox, account: account, campaign_type: :one_off)
      allow(sms).to receive(:audience_contacts).and_return(resolved)
      allow_any_instance_of(Sms::OneoffSmsCampaignService).to receive(:channel).and_return(sms_channel) # rubocop:disable RSpec/AnyInstance

      expect(sms_channel).not_to receive(:send_text_message)

      Sms::OneoffSmsCampaignService.new(campaign: sms).perform
    end
  end

  describe 'precedence' do
    let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-9') }
    let(:campaign) { create(:campaign, account: account, campaign_type: :one_off, commerce_store: store) }

    # Negatives union: the native store can refuse a partner-originated send even when the
    # partner has a perfectly good grant on file.
    it 'lets a native opt-out refuse a send the partner granted' do
      PartnerConsent.create!(platform_app: create(:platform_app), account: account, commerce_store: store,
                             contact: shopper, external_subject_id: 'e1', purpose: :promotional, channel: :any,
                             state: :granted, source: 'checkout_optin', captured_at: Time.current)
      stop(shopper)

      expect(described_class.refusal(shopper, campaign, :whatsapp)).to eq(:consent_withdrawn)
    end

    it 'puts the kill switch ahead of everything else' do
      account.update!(settings: account.settings.merge('campaign_sending_halted' => true))

      expect(described_class.refusal(shopper, campaign, :whatsapp)).to eq(:outbound_halted)
    end

    # Every code the guard can return has a sentence, or a skip would crash the sender that
    # tried to record it.
    it 'has a recorded reason for every refusal it can return' do
      codes = %i[outbound_halted installation_revoked contact_unavailable messaging_suppressed
                 consent_withdrawn partner_suppressed partner_consent_withdrawn
                 promotional_consent_missing partner_consent_missing partner_scope_mismatch]

      expect(Campaigns::RecipientSnapshot::CONSENT_REASONS.keys).to include(*codes)
    end
  end
end
