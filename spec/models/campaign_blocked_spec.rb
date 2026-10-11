require 'rails_helper'

# DECISION 6. A scheduled WhatsApp campaign whose capability is unavailable used to return silently from
# `trigger!`, keep reading `active`, be retried every five minutes for three days and then be abandoned with
# nothing recorded anywhere. These examples assert the replacement, and the last group asserts the thing that
# must NOT have changed: `trigger!` is shared with SMS.
RSpec.describe Campaign, type: :model do
  let(:account) { create(:account) }

  let(:whatsapp_campaign) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    create(:campaign, account: account, inbox: channel.inbox, scheduled_at: 1.hour.ago)
  end

  let(:sms_campaign) do
    create(:campaign, account: account, inbox: create(:channel_sms, account: account).inbox, scheduled_at: 1.hour.ago)
  end

  def signals_for(campaign)
    Operations::Signal.where(subject_type: 'Campaign', subject_id: campaign.id)
  end

  describe 'a WhatsApp campaign reaching its send time without the capability' do
    before { account.disable_features!('whatsapp_campaign') }

    it 'does not send' do
      expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

      whatsapp_campaign.trigger!
    end

    it 'moves to the explicit blocked state with a machine-readable reason' do
      whatsapp_campaign.trigger!

      expect(whatsapp_campaign.reload).to have_attributes(campaign_status: 'blocked',
                                                          blocked_reason: described_class::BLOCKED_FEATURE_DISABLED)
    end

    it 'preserves the campaign and its audience' do
      audience = whatsapp_campaign.audience
      message = whatsapp_campaign.message

      whatsapp_campaign.trigger!

      expect(whatsapp_campaign.reload).to have_attributes(audience: audience, message: message)
    end

    it 'emits exactly one Operations signal, naming the capability' do
      whatsapp_campaign.trigger!

      signal = signals_for(whatsapp_campaign).sole
      expect(signal).to have_attributes(source: 'campaign', signal: 'feature_disabled', severity: 'warning',
                                        account_id: account.id, resolved_at: nil)
      expect(signal.detail).to include('capability' => 'whatsapp_campaign')
    end

    it 'keeps the campaign message and audience out of the signal' do
      whatsapp_campaign.trigger!

      signal = signals_for(whatsapp_campaign).sole
      expect(signal.reason).not_to include(whatsapp_campaign.message)
      expect(signal.detail.keys).to contain_exactly('capability', 'inbox_id')
    end

    # The dedup requirement stated as a behaviour rather than as an index: the scheduler polls, and a signal per
    # poll is the noise this is meant to avoid.
    it 'does not add a second signal when the campaign is triggered again' do
      3.times { whatsapp_campaign.trigger! }

      expect(signals_for(whatsapp_campaign).count).to eq(1)
    end

    it 'stays idempotent on repeated execution' do
      whatsapp_campaign.trigger!
      blocked_at = whatsapp_campaign.reload.updated_at

      expect { whatsapp_campaign.trigger! }.not_to(change { whatsapp_campaign.reload.campaign_status })
      expect(whatsapp_campaign.reload.updated_at).to be_within(1.second).of(blocked_at)
    end
  end

  describe 'not being retried or abandoned' do
    before do
      account.disable_features!('whatsapp_campaign')
      whatsapp_campaign.trigger!
    end

    it 'is no longer selected by the scheduler, so there are no further retries' do
      expect(Campaigns::TriggerOneoffCampaignJob).not_to receive(:perform_later)

      TriggerScheduledItemsJob.perform_now
    end

    # The old behaviour's second half: after three days the campaign fell out of the selection window and was
    # abandoned with nothing recorded. It is still not selected -- but now it holds a state and a reason that
    # say so, which is the difference between blocked and abandoned.
    it 'still says what happened after the old abandonment window has passed' do
      travel_to(5.days.from_now) do
        TriggerScheduledItemsJob.perform_now

        expect(whatsapp_campaign.reload).to have_attributes(campaign_status: 'blocked',
                                                            blocked_reason: described_class::BLOCKED_FEATURE_DISABLED)
      end
    end

    it 'cannot be flipped to processing by a job that was already in flight' do
      account.enable_features!('whatsapp_campaign')

      expect(whatsapp_campaign.send(:mark_processing!)).to be_falsey
      expect(whatsapp_campaign.reload.campaign_status).to eq('blocked')
    end
  end

  describe '#unblock!' do
    before do
      account.disable_features!('whatsapp_campaign')
      whatsapp_campaign.trigger!
      account.enable_features!('whatsapp_campaign')
    end

    it 'returns the campaign to active and clears the reason' do
      whatsapp_campaign.unblock!

      expect(whatsapp_campaign.reload).to have_attributes(campaign_status: 'active', blocked_reason: nil)
    end

    it 'leaves a scheduled time that is still inside the selection window alone' do
      scheduled_at = whatsapp_campaign.reload.scheduled_at

      whatsapp_campaign.unblock!

      expect(whatsapp_campaign.reload.scheduled_at).to be_within(1.second).of(scheduled_at)
    end

    # Without this the resume is theoretical: the scheduler would never select the campaign again, which is the
    # same silence from the other direction.
    it 'moves a scheduled time that has fallen outside the window forward, so the resume is real' do
      whatsapp_campaign.update_column(:scheduled_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations

      whatsapp_campaign.unblock!

      expect(whatsapp_campaign.reload.scheduled_at).to be_within(1.minute).of(Time.current)
    end

    it 'is selected by the scheduler once it is active again' do
      whatsapp_campaign.unblock!

      expect(Campaigns::TriggerOneoffCampaignJob).to receive(:perform_later).with(whatsapp_campaign)

      TriggerScheduledItemsJob.perform_now
    end

    it 'refuses to act on a campaign that is not blocked' do
      whatsapp_campaign.unblock!

      expect(whatsapp_campaign.unblock!).to be(false)
    end
  end

  describe 'cancellation, which is the other way out' do
    it 'can still be deleted while blocked, with its recipient data' do
      account.disable_features!('whatsapp_campaign')
      whatsapp_campaign.trigger!

      expect { whatsapp_campaign.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe 'the audience a blocked campaign still holds' do
    it 'counts as in use, so it cannot be deleted out from under the campaign' do
      audience = create(:custom_filter, account: account, filter_type: :contact, shared: true)
      whatsapp_campaign.update!(audience: [{ 'type' => Custom::CampaignAudience::AUDIENCE_TYPE, 'id' => audience.id }])
      account.disable_features!('whatsapp_campaign')
      whatsapp_campaign.trigger!

      expect(Audience::Usage.campaigns(audience)).to include(whatsapp_campaign)
    end
  end

  # THE REGRESSION SURFACE. `trigger!` is shared, and `feature_enabled?` is true for every inbox type that is
  # not WhatsApp -- so no SMS campaign can reach the new branch, whatever the whatsapp_campaign capability says.
  describe 'SMS, which must be untouched' do
    it 'sends with the whatsapp capability disabled' do
      account.disable_features!('whatsapp_campaign')

      expect(Sms::OneoffSmsCampaignService).to receive(:new).with(campaign: sms_campaign).and_return(
        instance_double(Sms::OneoffSmsCampaignService, perform: true)
      )

      sms_campaign.trigger!
    end

    it 'is never blocked' do
      account.disable_features!('whatsapp_campaign')
      allow(Sms::OneoffSmsCampaignService).to receive(:new).and_return(
        instance_double(Sms::OneoffSmsCampaignService, perform: true)
      )

      sms_campaign.trigger!

      expect(sms_campaign.reload.campaign_status).to eq('processing')
      expect(sms_campaign.blocked_reason).to be_nil
    end

    it 'records no campaign signal' do
      account.disable_features!('whatsapp_campaign')
      allow(Sms::OneoffSmsCampaignService).to receive(:new).and_return(
        instance_double(Sms::OneoffSmsCampaignService, perform: true)
      )

      sms_campaign.trigger!

      expect(signals_for(sms_campaign)).to be_empty
    end
  end

  describe 'a WhatsApp campaign that does have the capability' do
    it 'sends as before' do
      account.enable_features!('whatsapp_campaign')

      expect(Whatsapp::OneoffCampaignService).to receive(:new).with(campaign: whatsapp_campaign).and_return(
        instance_double(Whatsapp::OneoffCampaignService, perform: true)
      )

      whatsapp_campaign.trigger!
      expect(whatsapp_campaign.reload.campaign_status).to eq('processing')
    end
  end
end
