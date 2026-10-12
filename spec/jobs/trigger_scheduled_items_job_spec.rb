require 'rails_helper'

RSpec.describe TriggerScheduledItemsJob do
  subject(:job) { described_class.perform_later }

  let(:account) { create(:account) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .on_queue('scheduled_jobs')
  end

  it 'triggers Conversations::ReopenSnoozedConversationsJob' do
    expect(Conversations::ReopenSnoozedConversationsJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Notification::ReopenSnoozedNotificationsJob' do
    expect(Notification::ReopenSnoozedNotificationsJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Account::ConversationsResolutionSchedulerJob' do
    expect(Account::ConversationsResolutionSchedulerJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Channels::Whatsapp::TemplatesSyncSchedulerJob' do
    expect(Channels::Whatsapp::TemplatesSyncSchedulerJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'does not trigger the hourly WhatsApp health scheduler' do
    expect(Channels::Whatsapp::HealthSyncSchedulerJob).not_to receive(:perform_later)

    described_class.perform_now
  end

  context 'when unexecuted Scheduled campaign jobs' do
    let!(:twilio_sms) { create(:channel_twilio_sms, account: account) }
    let!(:twilio_inbox) { create(:inbox, channel: twilio_sms, account: account) }

    it 'triggers Campaigns::TriggerOneoffCampaignJob' do
      campaign = create(:campaign, inbox: twilio_inbox, account: account)
      create(:campaign, inbox: twilio_inbox, account: account, scheduled_at: 10.days.after)
      expect(Campaigns::TriggerOneoffCampaignJob).to receive(:perform_later).with(campaign).once
      described_class.perform_now
    end

    it 'does not trigger campaigns that are already processing' do
      create(:campaign, inbox: twilio_inbox, account: account, campaign_status: :processing)

      expect(Campaigns::TriggerOneoffCampaignJob).not_to receive(:perform_later)

      described_class.perform_now
    end

    # DECISION 6, at the selection level rather than the model level. The whole point of a blocked campaign is
    # that it stops being picked up: a campaign the scheduler still selects every minute is the active retry
    # loop the decision forbids, and nothing else in the suite asserts the scheduler's half of that.
    it 'does not trigger a blocked campaign' do
      create(:campaign, inbox: twilio_inbox, account: account, campaign_status: :blocked,
                        blocked_reason: Campaign::BLOCKED_FEATURE_DISABLED)

      expect(Campaigns::TriggerOneoffCampaignJob).not_to receive(:perform_later)

      described_class.perform_now
    end

    # Campaign#unblock! compares against this constant to decide whether a resumed campaign's scheduled time
    # still means anything (campaign.rb:91). If the two drift apart, re-activating a campaign blocked for
    # longer than the window silently does nothing -- the exact silence the decision exists to remove.
    it 'selects on the same window Campaign#unblock! reads' do
      expect(described_class::SELECTION_WINDOW).to eq(3.days)

      campaign = create(:campaign, inbox: twilio_inbox, account: account,
                                   scheduled_at: described_class::SELECTION_WINDOW.ago - 1.hour)

      expect(Campaigns::TriggerOneoffCampaignJob).not_to receive(:perform_later)
      described_class.perform_now

      campaign.update!(campaign_status: :blocked, blocked_reason: Campaign::BLOCKED_FEATURE_DISABLED)
      campaign.unblock!

      expect(campaign.reload.scheduled_at).to be_within(1.minute).of(Time.current)
    end
  end
end
