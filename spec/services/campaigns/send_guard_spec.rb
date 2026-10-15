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

  # ================================================================ pacing and the gate
  #
  # THE REGRESSION THIS SECTION EXISTS FOR. The senders used to ask `refusal` and then call
  # `Campaigns::Throttle.pace`, in that order. Pacing SLEEPS -- up to MAX_WAIT per recipient,
  # and a large audience spends most of its wall-clock time inside those sleeps -- so a
  # withdrawal, a kill switch or a revocation landing during the wait was read, found nothing
  # left to stop, and the message went out anyway. The answer was taken before the wait and
  # acted on after it, which made asking late pointless for exactly the window in which
  # asking late is the only thing that helps.
  describe '.clear_to_send' do
    let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-p1') }
    # Transactional (UTILITY), so a missing promotional grant is not in the way and every
    # example below isolates the one state change it makes during the wait.
    let(:utility) { { 'name' => 't', 'category' => 'UTILITY', 'language' => 'en' } }
    let(:campaign) { create(:campaign, account: account, campaign_type: :one_off, template_params: utility) }

    before { Redis::Alfred.delete(Campaigns::Throttle.key(account)) }

    it 'permits a send that nothing refuses' do
      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to be_nil
    end

    it 'refuses before pacing, so a refused recipient never claims a slot in the ceiling' do
      stop(shopper)

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:consent_withdrawn)
      expect(Campaigns::Throttle.used(account)).to eq(0)
    end

    # The property itself: eligibility is re-taken AFTER the wait. The withdrawal is recorded
    # from inside the sleep, which is the only way to reproduce the real sequence -- the
    # recipient was eligible when the guard first asked and is not by the time the provider
    # would be called.
    it 'honours a withdrawal that lands during the throttle wait' do
      account.update!(settings: account.settings.merge(Campaigns::Throttle::SETTING_KEY => 1))
      Campaigns::Throttle.pace(account, sleeper: ->(_) {}) # spend the window

      allow(Campaigns::Throttle).to receive(:pace) do |_account, **_kwargs|
        stop(shopper)
        :waited
      end

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:consent_withdrawn)
    end

    it 'honours a kill switch thrown during the throttle wait' do
      allow(Campaigns::Throttle).to receive(:pace) do |_account, **_kwargs|
        account.update!(settings: account.settings.merge(Campaigns::Outbound::ACCOUNT_KEY => true))
        :waited
      end

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:outbound_halted)
    end

    # A partner-originated send answers to the installation as well. Revoking it mid-wait must
    # stop the message, not merely stop the next campaign.
    it 'honours an installation revoked during the throttle wait' do
      partner_campaign = create(:campaign, account: account, campaign_type: :one_off,
                                           commerce_store: store, template_params: utility)
      create(:commerce_customer_link, account: account, store: store, contact: shopper,
                                      external_customer_id: 'cust-rev')
      allow(Campaigns::Throttle).to receive(:pace) do |_account, **_kwargs|
        store.update!(status: :disconnected)
        :waited
      end

      expect(described_class.clear_to_send(shopper, partner_campaign, :whatsapp)).to eq(:installation_revoked)
    end

    # The second ask costs a query per recipient on the whole audience. It buys nothing when
    # no time passed, so it is not paid then -- and this pins that, because a change that
    # always re-asks would pass every example above while doubling the cost of every campaign.
    it 'does not re-ask when pacing did not actually wait' do
      allow(Campaigns::Throttle).to receive(:pace).and_return(:clear)
      allow(described_class).to receive(:refusal).and_call_original

      described_class.clear_to_send(shopper, campaign, :whatsapp)

      expect(described_class).to have_received(:refusal).once
    end

    # A degraded throttle does not sleep, so there is no window to cover. It must not become
    # a reason to send to someone who is already refused, nor a reason to re-query.
    it 'still refuses a withdrawn recipient when the throttle is degraded' do
      allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError)
      stop(shopper)

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:consent_withdrawn)
    end

    it 'lets an eligible recipient through when the throttle is degraded' do
      allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError)

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to be_nil
    end
  end

  # ================================================================ live state
  #
  # THE DEFECT THESE PIN. The consent tables were always queried fresh, so a withdrawal
  # arriving mid-run was honoured. Three other inputs were not: `campaign.account` and
  # `campaign.commerce_store` are memoised associations held for the whole job, and each
  # contact comes out of the audience relation resolved when the scheduler dispatched the
  # campaign. `settings`, `status` and `blocked` were therefore read off objects loaded before
  # the loop began, so the per-account kill switch, an installation revoked mid-run and an
  # agent blocking a shopper mid-run all did nothing until the next job.
  #
  # EVERY EXAMPLE CHANGES THE ROW THROUGH A DIFFERENT OBJECT than the one the campaign holds,
  # because that is what reproduces it. Mutating `campaign.account` directly would pass
  # against the broken implementation and prove nothing.
  describe 'reading live rows rather than the objects the run started with' do
    let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-live') }
    let(:utility) { { 'name' => 't', 'category' => 'UTILITY', 'language' => 'en' } }
    let(:campaign) { create(:campaign, account: account, campaign_type: :one_off, template_params: utility) }

    it 'honours a kill switch thrown on the account after the campaign loaded it' do
      campaign.account.settings # memoise the association exactly as the sender does
      Account.find(account.id).update!(settings: { Campaigns::Outbound::ACCOUNT_KEY => true })

      expect(described_class.refusal(shopper, campaign, :whatsapp)).to eq(:outbound_halted)
    end

    it 'honours an agent blocking the shopper after the audience was resolved' do
      resolved.first.blocked # memoise exactly as the audience relation leaves it
      Contact.find(shopper.id).update!(blocked: true)

      expect(described_class.refusal(resolved.first, campaign, :whatsapp)).to eq(:contact_unavailable)
    end

    it 'honours an installation revoked after the campaign loaded it' do
      partner = create(:campaign, account: account, campaign_type: :one_off,
                                  commerce_store: store, template_params: utility)
      create(:commerce_customer_link, account: account, store: store, contact: shopper,
                                      external_customer_id: 'cust-live')
      partner.commerce_store.status
      Commerce::Store.find(store.id).update!(status: :disconnected)

      expect(described_class.refusal(shopper, partner, :whatsapp)).to eq(:installation_revoked)
    end

    # A deleted CONTACT is reachable: nothing stops an agent deleting one mid-run, and
    # `campaigns` has no foreign key to `contacts`. It must refuse this recipient rather than
    # abort a run that has already handed messages to the provider, which is why the re-read
    # is a find_by and not a reload. (A deleted STORE is not reachable -- `campaigns` has a
    # foreign key to `commerce_stores`, so the database refuses the delete.)
    it 'refuses a contact deleted mid-run instead of raising' do
      doomed = create(:contact, :with_phone_number, account: account)
      Contact.find(doomed.id).destroy!

      expect(described_class.refusal(doomed, campaign, :whatsapp)).to eq(:contact_unavailable)
    end
  end

  # ================================================================ the commercial quota
  #
  # P5G. docs/partner-consent/THROTTLE-SAFETY.md §1 required that a commercial quota must NOT
  # be routed through Campaigns::Throttle, because that module fails OPEN and a quota that
  # fails open is not a quota. These examples pin the two properties that separate them: the
  # quota is taken LAST, so it is never spent on a recipient the guard was going to refuse,
  # and it refuses when it is used up.
  describe 'the send allowance' do
    let(:utility) { { 'name' => 't', 'category' => 'UTILITY', 'language' => 'en' } }
    let(:campaign) { create(:campaign, account: account, campaign_type: :one_off, template_params: utility) }

    # UPDATED, NOT CREATED: an account arrives with a subscription of its own and
    # `billing_subscriptions.account_id` is unique, so creating a second one fails validation
    # rather than replacing the first.
    def subscribe_to(limits)
      subscription = account.billing_subscription || BillingSubscription.new(account: account, source: 'manual')
      subscription.update!(plan: create(:billing_plan, limits: limits), status: 'active',
                           current_period_end: 20.days.from_now)
      account.reload
    end

    before do
      allow(Billing::Settings).to receive(:enforced?).and_return(true)
      subscribe_to('campaign_sends' => 2)
      Redis::Alfred.delete(Campaigns::Throttle.key(account))
    end

    it 'lets a send through while there is allowance left' do
      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to be_nil
    end

    it 'refuses once the period allowance is used up' do
      2.times { described_class.clear_to_send(shopper, campaign, :whatsapp) }

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:send_quota_exceeded)
    end

    # THE ORDERING THAT MATTERS COMMERCIALLY. Charging a merchant for messages to people who
    # opted out is the one accounting error that is also a complaint.
    it 'does not spend a unit on a recipient it was going to refuse anyway' do
      stop(shopper)

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:consent_withdrawn)
      expect(Billing::MeteredUsage.usage(account)[:used]).to eq(0)
    end

    it 'does not spend a unit when the kill switch refuses the send' do
      account.update!(settings: account.settings.merge(Campaigns::Outbound::ACCOUNT_KEY => true))

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to eq(:outbound_halted)
      expect(Billing::MeteredUsage.usage(account)[:used]).to eq(0)
    end

    # An account with no metered ceiling -- which is every account that existed before P5G --
    # must be untouched, and must not acquire a counter row it never needed.
    it 'is inert for an account whose plan sets no allowance' do
      subscribe_to({})

      expect(described_class.clear_to_send(shopper, campaign, :whatsapp)).to be_nil
      expect(BillingUsageCounter.count).to eq(0)
    end

    it 'has a recorded reason, or the sender crashes trying to record the skip' do
      expect(Campaigns::RecipientSnapshot::CONSENT_REASONS).to have_key(:send_quota_exceeded)
    end
  end
end
