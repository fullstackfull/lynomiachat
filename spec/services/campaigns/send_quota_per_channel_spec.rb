require 'rails_helper'

# EVERY CHANNEL SPENDS THE ALLOWANCE, AND ONLY FOR A MESSAGE IT ACTUALLY SENDS.
#
# The quota used to be taken inside `Campaigns::SendGuard.clear_to_send`, which is one call
# site and looked safe. It was not: that gate runs before each sender's OWN checks, and a
# recipient those refuse is never handed to a provider. A WhatsApp campaign addressing
# contacts with no WhatsApp destination charged a merchant's paid allowance for every one of
# them. So the unit moved to the line before the message goes, which is a different line in
# each sender -- and the cost of that is a call site somebody can forget, which would make a
# channel silently UNMETERED.
#
# This file is what makes forgetting it fail. One example per sender, each asserting the
# same two things: a message that goes spends exactly one unit, and the ceiling refuses.
RSpec.describe 'the send allowance, per channel', type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan, limits: { 'campaign_sends' => 2 }) }

  def subscribe
    subscription = account.billing_subscription || BillingSubscription.new(account: account, source: 'manual')
    subscription.update!(plan: plan, status: 'active', current_period_end: 20.days.from_now)
    account.reload
  end

  def shoppers(count)
    Array.new(count) do |index|
      create(:contact, account: account, phone_number: "+96350000#{format('%<n>03d', n: index)}").tap do |contact|
        Commerce::MessagingConsents.record(
          account: account, contact: contact,
          decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
        )
      end
    end
  end

  before do
    allow(Billing::Settings).to receive(:enforced?).and_return(true)
    subscribe
    Redis::Alfred.delete(Campaigns::Throttle.key(account))
  end

  shared_examples 'a metered sender' do
    it 'spends one unit per message it sends, and stops at the ceiling' do
      audience = shoppers(3)
      allow(campaign).to receive(:audience_contacts).and_return(audience)

      service.perform

      expect(sent.size).to eq(2), 'the third message must be refused by the ceiling, not sent'
      expect(Billing::MeteredUsage.usage(account)[:used]).to eq(2)
    end

    it 'spends nothing when every recipient is refused before the send' do
      audience = shoppers(2)
      audience.each do |contact|
        Commerce::MessagingConsents.record(
          account: account, contact: contact,
          decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
        )
      end
      allow(campaign).to receive(:audience_contacts).and_return(audience)

      service.perform

      expect(sent).to be_empty
      expect(Billing::MeteredUsage.usage(account)[:used]).to eq(0)
    end
  end

  describe Sms::OneoffSmsCampaignService do
    let(:channel) { create(:channel_sms, account: account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
    end
    let(:sent) { [] }
    let(:service) { described_class.new(campaign: campaign) }

    before do
      allow(channel).to receive(:send_text_message) { |to, _content| sent << to }
      allow(service).to receive(:channel).and_return(channel)
    end

    it_behaves_like 'a metered sender'
  end

  describe Twilio::OneoffSmsCampaignService do
    let(:channel) { create(:channel_twilio_sms, account: account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
    end
    let(:sent) { [] }
    let(:service) { described_class.new(campaign: campaign) }

    before do
      allow(channel).to receive(:send_message) { |to:, body:| (sent << to) && body }
      allow(service).to receive(:channel).and_return(channel)
    end

    it_behaves_like 'a metered sender'
  end

  # WhatsApp is the one the defect was found in: its sender refuses a contact with no
  # WhatsApp destination AFTER the eligibility gate, so a unit taken in the gate was spent on
  # somebody Meta never heard about.
  describe Whatsapp::OneoffCampaignService do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false)
    end
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago,
                        template_params: { 'name' => 'promo', 'category' => 'MARKETING', 'language' => 'en',
                                           'processed_params' => {} })
    end
    let(:sent) { [] }
    let(:service) { described_class.new(campaign: campaign) }

    before do
      account.enable_features!('whatsapp_campaign')
      # The approved template the sender resolves before it calls Meta. Stubbed rather than
      # fixtured because what is under test is the allowance, not template resolution --
      # but stubbed at the PROCESSOR, so the sender's own destination and parameter checks
      # above it still run for real, which is where the defect lived.
      allow(Whatsapp::TemplateProcessorService).to receive(:new).and_return(
        instance_double(Whatsapp::TemplateProcessorService, call: ['promo', nil, 'en', []])
      )
      allow(channel).to receive(:send_template) { |to, _params, _arg| sent << to and "wamid.#{to}" }
      allow(service).to receive(:channel).and_return(channel)
    end

    it_behaves_like 'a metered sender'

    # THE DEFECT ITSELF. These contacts are in the audience and pass every consent check, and
    # the sender then finds no WhatsApp destination for them. Nothing reaches Meta, so
    # nothing may be charged.
    it 'spends nothing on recipients it finds no WhatsApp destination for' do
      audience = Array.new(2) do
        create(:contact, account: account).tap do |contact|
          Commerce::MessagingConsents.record(
            account: account, contact: contact,
            decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
          )
        end
      end
      allow(campaign).to receive(:audience_contacts).and_return(audience)

      service.perform

      expect(sent).to be_empty
      expect(Billing::MeteredUsage.usage(account)[:used]).to eq(0)
    end
  end
end
