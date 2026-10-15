require 'rails_helper'

# A CANCELLATION STOPS THE RUN, NOT JUST THE SENDS.
#
# Campaigns::SendGuard refuses each remaining recipient with :campaign_cancelled, which is
# correct and was all that happened: the sender then walked the rest of the audience, asking
# two queries and writing one skip row per head, to reach a conclusion it already had. A
# 100k-recipient campaign cancelled a minute in spent the remaining ~99k iterations on it.
#
# A cancellation is a fact about the CAMPAIGN and is identical for everyone left, so the loop
# stops and one UPDATE records the rest. These examples pin both halves -- stopping, and the
# rows still saying what happened, because a row left `queued` reads on the analytics page as
# a run that never finished.
RSpec.describe 'cancelling a campaign mid-run', type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:audience) do
    create_list(:contact, 4, :with_phone_number, account: account).each do |contact|
      Commerce::MessagingConsents.record(
        account: account, contact: contact,
        decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
      )
    end
  end

  before { Redis::Alfred.delete(Campaigns::Throttle.key(account)) }

  shared_examples 'a sender that stops' do
    it 'stops asking the guard once the campaign is cancelled' do
      allow(Campaigns::SendGuard).to receive(:clear_to_send).and_wrap_original do |original, *args|
        campaign.cancel! unless campaign.reload.cancelled?
        original.call(*args)
      end

      service.perform

      # One call: the first recipient cancels it and is refused, and nobody after is asked.
      expect(Campaigns::SendGuard).to have_received(:clear_to_send).once
    end
  end

  context 'with the SMS sender' do
    let(:channel) { create(:channel_sms, account: account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
    end
    let(:service) { Sms::OneoffSmsCampaignService.new(campaign: campaign) }

    before do
      allow(campaign).to receive(:audience_contacts).and_return(audience)
      allow(channel).to receive(:send_text_message)
    end

    it_behaves_like 'a sender that stops'

    # There is no recipient snapshot on this path -- the analytics package is WhatsApp-only
    # and nothing seeds rows for an SMS campaign -- so the only record that the run stopped
    # is that it stopped sending.
    it 'sends to nobody after the cancellation' do
      campaign.cancel!

      service.perform

      expect(channel).not_to have_received(:send_text_message)
    end
  end

  # THE THIRD SENDER. B2.4 changed three send loops and this suite covered two of them, so
  # reverting the `break` in this one left every example green -- the gap an audit of the
  # closure found, not a run. Twilio SMS is a campaign channel a merchant can actually be on.
  context 'with the Twilio SMS sender' do
    let(:channel) { create(:channel_twilio_sms, account: account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
    end
    let(:service) { Twilio::OneoffSmsCampaignService.new(campaign: campaign) }

    before do
      allow(campaign).to receive(:audience_contacts).and_return(audience)
      allow(channel).to receive(:send_message)
    end

    it_behaves_like 'a sender that stops'

    # Only the shared example pins the `break`: SendGuard refuses every recipient of a
    # cancelled campaign either way, so this one stays green without it. It guards the
    # record -- nobody is messaged -- rather than the cost of reaching it.
    it 'sends to nobody after the cancellation' do
      campaign.cancel!

      service.perform

      expect(channel).not_to have_received(:send_message)
    end
  end

  context 'with the WhatsApp sender' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false,
                                message_templates: [{ 'name' => 'promo', 'language' => 'en',
                                                      'status' => 'approved', 'category' => 'MARKETING' }])
    end
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago,
                        template_params: { 'name' => 'promo', 'language' => 'en', 'processed_params' => {} })
    end
    let(:service) { Whatsapp::OneoffCampaignService.new(campaign: campaign) }

    before do
      account.enable_features!('whatsapp_campaign')
      allow(campaign).to receive(:audience_contacts).and_return(account.contacts.where(id: audience.map(&:id)))
      allow(channel).to receive(:send_template).and_return('wamid.x')
      allow(service).to receive(:channel).and_return(channel)
    end

    it_behaves_like 'a sender that stops'

    # THE ROWS STILL HAVE TO SAY WHAT HAPPENED. The snapshot is seeded before the loop, so
    # breaking out of it leaves everyone after the cancellation `queued` -- which the
    # analytics page reads as a run still in progress, for a campaign that has stopped.
    #
    # These next two pass against the OLD code as well, and deliberately so: walking the
    # whole audience also leaves nobody queued, because it records each one in turn. They
    # are here to stop the optimisation losing the record, not to prove it -- the examples
    # that go red without the fix are the two `stops asking the guard` ones and the single
    # UPDATE below.
    it 'leaves nobody queued, so the results page does not read as still running' do
      campaign.cancel!

      service.perform

      expect(CampaignRecipient.where(campaign_id: campaign.id, status: :queued)).to be_empty
    end

    it 'says why, in the vocabulary the skip breakdown groups on' do
      campaign.cancel!

      service.perform

      reasons = CampaignRecipient.where(campaign_id: campaign.id).distinct.pluck(:error_message)
      expect(reasons).to eq([Campaigns::RecipientSnapshot::CONSENT_REASONS.fetch(:campaign_cancelled)])
    end

    # And one statement for all of them, which is the point of stopping.
    it 'records the remainder without a query per head' do
      campaign.cancel!
      updates = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
        updates += 1 if payload[:sql].to_s.start_with?('UPDATE "campaign_recipients"')
      end

      service.perform
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(updates).to eq(1)
    end
  end
end
