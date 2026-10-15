require 'rails_helper'

describe Sms::OneoffSmsCampaignService do
  subject(:sms_campaign_service) { described_class.new(campaign: campaign) }

  let(:account) { create(:account) }
  let!(:sms_channel) { create(:channel_sms, account: account) }
  let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let(:label1) { create(:label, account: account) }
  let(:label2) { create(:label, account: account) }
  let!(:campaign) do
    create(:campaign, inbox: sms_inbox, account: account,
                      audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }])
  end

  # An SMS blast carries no provider category, so Campaigns::Eligibility reads it as
  # promotional and it reaches nobody without a recorded grant. These examples are about the
  # sending mechanics rather than the consent rule, so the grant is recorded -- through the
  # real writer -- for whoever the example just created. The refusal paths have their own
  # coverage in spec/services/campaigns/eligibility_spec.rb.
  def allow_marketing_to_everyone
    account.contacts.find_each do |contact|
      Commerce::MessagingConsents.record(
        account: account, contact: contact,
        decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant',
                                                            purposes: ['promotional'])
      )
    end
  end

  describe 'perform' do
    before do
      stub_request(:post, 'https://messaging.bandwidth.com/api/v2/users/1/messages').to_return(
        status: 200,
        body: { 'id' => '1' }.to_json,
        headers: {}
      )
      allow_any_instance_of(described_class).to receive(:channel).and_return(sms_channel) # rubocop:disable RSpec/AnyInstance
    end

    it 'raises error if the campaign is completed' do
      campaign.completed!

      expect { sms_campaign_service.perform }.to raise_error 'Completed Campaign'
    end

    it 'raises error invalid campaign when its not a oneoff sms campaign' do
      campaign = create(:campaign)

      expect { described_class.new(campaign: campaign).perform }.to raise_error "Invalid campaign #{campaign.id}"
    end

    it 'send messages to contacts in the audience and marks the campaign completed' do
      contact_with_label1, contact_with_label2, contact_with_both_labels = FactoryBot.create_list(:contact, 3, :with_phone_number, account: account)
      contact_with_label1.update_labels([label1.title])
      contact_with_label2.update_labels([label2.title])
      contact_with_both_labels.update_labels([label1.title, label2.title])
      allow_marketing_to_everyone
      sms_campaign_service.perform
      assert_requested(:post, 'https://messaging.bandwidth.com/api/v2/users/1/messages', times: 3)
      expect(campaign.reload.completed?).to be true
    end

    it 'marks the campaign completed after processing the audience' do
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label1.title])

      expect(sms_channel).to receive(:send_text_message) do
        expect(campaign.reload.completed?).to be false
      end

      allow_marketing_to_everyone
      sms_campaign_service.perform

      expect(campaign.reload.completed?).to be true
    end

    it 'uses liquid template service to process campaign message' do
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label1.title])

      expect(Liquid::CampaignTemplateService).to receive(:new).with(campaign: campaign, contact: contact).and_call_original

      allow_marketing_to_everyone
      sms_campaign_service.perform
    end

    it 'continues processing contacts when sending message raises an error' do
      contact_error, contact_success = FactoryBot.create_list(:contact, 2, :with_phone_number, account: account)
      contact_error.update_labels([label1.title])
      contact_success.update_labels([label1.title])

      error_message = 'SMS provider error'

      expect(sms_channel).to receive(:send_text_message).with(contact_error.phone_number, anything).and_raise(StandardError, error_message)
      expect(sms_channel).to receive(:send_text_message).with(contact_success.phone_number, anything).and_return(nil)

      expect(Rails.logger).to receive(:error).with("[SMS Campaign #{campaign.id}] Failed to send to #{contact_error.phone_number}: #{error_message}")

      allow_marketing_to_everyone
      sms_campaign_service.perform
      expect(campaign.reload.completed?).to be true
    end
  end
end
