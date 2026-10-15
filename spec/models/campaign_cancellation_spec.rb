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
      # AND THE RECORD HAS TO SAY SO AFTERWARDS. Every sender ends with `campaign.completed!`
      # once its loop returns, and the loop returns NORMALLY when a cancellation stopped it --
      # Campaigns::SendGuard refuses each remaining recipient rather than raising. So the
      # status an operator watched change to `cancelled` was overwritten by `completed` a
      # moment later, and the only account anyone can read afterwards said the campaign had
      # finished sending when a person had stopped it. The sends did stop; the record lied.
      expect(campaign.reload).to be_cancelled
      expect(campaign.blocked_reason).to be_nil
    end

    # The same property stated on its own, because the example above would still pass if the
    # loop stopped for any other reason.
    it 'is not moved out of cancelled by the sender finishing its loop' do
      campaign.cancel!('wrong audience')

      expect(campaign.completed!).to be(false)

      expect(campaign.reload).to be_cancelled
      expect(campaign.blocked_reason).to eq('wrong audience')
      expect(campaign.completed_at).to be_nil
    end

    it 'has a recorded skip reason, or the sender crashes trying to record it' do
      expect(Campaigns::RecipientSnapshot::CONSENT_REASONS).to have_key(:campaign_cancelled)
    end
  end

  # CANCELLING A BLOCKED CAMPAIGN, which this handled by destroying the evidence.
  #
  # `blocked_reason` was overwritten with `reason.presence` whatever the campaign's state,
  # so cancelling a campaign the system had blocked -- with the reason box empty, the normal
  # way to cancel -- erased BLOCKED_FEATURE_DISABLED, the only record of why it never went
  # out. And the Operations signal the block opened is resolved only by `unblock!`, which
  # refuses anything no longer `blocked?`; with no un-cancel, the feed asserted a capability
  # problem about a campaign nobody was going to send, permanently.
  describe 'cancelling a blocked campaign' do
    let(:whatsapp_inbox) do
      create(:inbox, account: account,
                     channel: create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                        sync_templates: false, validate_provider_config: false))
    end
    let(:blocked) do
      create(:campaign, account: account, inbox: whatsapp_inbox, campaign_type: :one_off,
                        scheduled_at: 1.hour.ago).tap(&:trigger!)
    end

    it 'is blocked to begin with, with its reason and an open signal' do
      expect(blocked.reload).to be_blocked
      expect(blocked.blocked_reason).to eq(Campaign::BLOCKED_FEATURE_DISABLED)
      expect(open_signals_for(blocked)).to eq(1)
    end

    it 'keeps the block reason when no cancellation reason is given' do
      blocked.cancel!

      expect(blocked.reload).to be_cancelled
      expect(blocked.blocked_reason).to eq(Campaign::BLOCKED_FEATURE_DISABLED)
    end

    it 'closes the capability signal, which nothing else would ever close' do
      blocked.cancel!

      expect(open_signals_for(blocked)).to eq(0)
    end

    it 'still records a reason the operator did give' do
      blocked.cancel!('superseded')

      expect(blocked.reload.blocked_reason).to eq('superseded')
    end

    # DELETING IS THE THIRD WAY OUT OF `blocked`, and it is the only one the Lynomia
    # dashboard offers: `unblock!` has no caller anywhere in the repository and the card
    # had no Stop button until this phase. A campaign simply removed left the Operations
    # feed asserting a capability problem about a campaign that no longer exists.
    it 'closes the signal when the campaign is deleted instead' do
      blocked

      expect { blocked.destroy! }.to change { open_signals_for(blocked) }.from(1).to(0)
    end

    def open_signals_for(record)
      Operations::Signal.where(account_id: record.account_id, source: :campaign, subject_type: 'Campaign',
                               subject_id: record.id, signal: :feature_disabled, resolved_at: nil).count
    end
  end
end
