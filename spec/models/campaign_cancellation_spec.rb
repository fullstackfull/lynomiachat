require 'rails_helper'

# CANCELLING A CAMPAIGN (P5D), and the promise this closes.
#
# docs/partner-consent/THROTTLE-SAFETY.md §3 recorded that the send boundary could not honour
# a cancellation because there was no cancellation to honour: `campaign_status` was
# active/completed/processing/blocked, and `blocked` is only ever set BEFORE a run begins.
# This is the state, and the guard that reads it.
#
# WHAT MAKES IT WORTH HAVING. A campaign is one job iterating its whole audience. A
# cancellation that only took effect on the next job would be no cancellation at all, because
# by the time the next job runs there is nothing left to stop. So the test that matters is the
# one where the campaign is cancelled WHILE the loop is running.
RSpec.describe Campaign do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_sms, account: account)) }
  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
  end

  describe '#cancel!' do
    it 'stops an active campaign and records why' do
      expect(campaign.cancel!('wrong audience')).to be(true)

      expect(campaign.reload).to be_cancelled
      expect(campaign.blocked_reason).to eq('wrong audience')
    end

    it 'stops a campaign that is already running' do
      campaign.processing!

      expect(campaign.cancel!).to be(true)
      expect(campaign.reload).to be_cancelled
    end

    # Nothing is left to stop, and saying otherwise would misreport what happened: the
    # messages went out.
    it 'refuses a campaign that has finished sending' do
      campaign.completed!

      expect(campaign.cancel!).to be_falsey
      expect(campaign.reload).to be_completed
    end

    it 'is idempotent' do
      campaign.cancel!('first')

      expect(campaign.cancel!('second')).to be_falsey
      expect(campaign.reload.blocked_reason).to eq('first')
    end

    it 'is never picked up by the scheduler again' do
      campaign.cancel!

      expect(Sms::OneoffSmsCampaignService).not_to receive(:new)

      campaign.trigger!
      expect(campaign.reload).to be_cancelled
    end

    # A job enqueued before the cancellation is a real independent path to mark_processing!,
    # and without the check there it would find the campaign and send it.
    it 'is not resurrected by a job that was already enqueued' do
      campaign.cancel!

      expect(campaign.send(:mark_processing!)).to be_falsey
      expect(campaign.reload).to be_cancelled
    end
  end

  # THE PROPERTY THE WHOLE FEATURE EXISTS FOR.
  describe 'at the send boundary' do
    include_context 'with commerce encryption'

    let(:shopper) { create(:contact, :with_phone_number, account: account, email: 's@example.test') }

    before do
      Commerce::MessagingConsents.record(
        account: account, contact: shopper,
        decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
      )
    end

    it 'refuses a recipient once the campaign is cancelled' do
      expect(Campaigns::SendGuard.refusal(shopper, campaign, :sms)).to be_nil

      described_class.find(campaign.id).cancel!

      expect(Campaigns::SendGuard.refusal(shopper, campaign, :sms)).to eq(:campaign_cancelled)
    end

    # Cancelled through a DIFFERENT object, because that is what reproduces it: the sender
    # holds the campaign it loaded when the run began, and a guard that read the held object
    # would never see the cancellation.
    it 'reads the cancellation off the live row, not the object the run started with' do
      campaign.campaign_status # memoise the association exactly as the sender does
      described_class.find(campaign.id).cancel!

      expect(Campaigns::SendGuard.refusal(shopper, campaign, :sms)).to eq(:campaign_cancelled)
    end

    it 'stops a run in flight at its next recipient' do
      contacts = create_list(:contact, 3, :with_phone_number, account: account)
      contacts.each do |contact|
        Commerce::MessagingConsents.record(
          account: account, contact: contact,
          decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
        )
      end
      allow(campaign).to receive(:audience_contacts).and_return(contacts)
      channel = campaign.inbox.channel
      sent = 0
      allow(channel).to receive(:send_text_message) do
        sent += 1
        # Cancelled from outside, after the first message has gone.
        described_class.find(campaign.id).cancel! if sent == 1
      end
      allow_any_instance_of(Sms::OneoffSmsCampaignService).to receive(:channel).and_return(channel) # rubocop:disable RSpec/AnyInstance

      Sms::OneoffSmsCampaignService.new(campaign: campaign).perform

      expect(sent).to eq(1), 'the loop must stop at the next recipient, not finish the audience'
    end

    it 'has a recorded skip reason, or the sender crashes trying to record it' do
      expect(Campaigns::RecipientSnapshot::CONSENT_REASONS).to have_key(:campaign_cancelled)
    end
  end
end
