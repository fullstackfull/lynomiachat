require 'rails_helper'

# P11.6 / P11.23 (docs/p11/05-usage-limits.md). The counted ceilings, and the channel permission that is a
# different rule wearing similar clothes.
RSpec.describe Billing::ResourceLimit do
  let(:account) { create(:account) }

  def subscribe(plan)
    BillingSubscription.create!(account: account, plan: plan, status: 'active', source: 'manual')
  end

  def add_inbox(name)
    account.inboxes.create!(name: name, channel: Channel::WebWidget.create!(account: account, website_url: "https://#{name}.example"))
  end

  describe 'the inbox ceiling' do
    before { subscribe(create(:billing_plan, limits: { 'inboxes' => 2 })) }

    it 'allows creation up to the ceiling' do
      expect { add_inbox('one') }.to change(Inbox, :count).by(1)
      expect { add_inbox('two') }.to change(Inbox, :count).by(1)
    end

    it 'refuses the one past it, in words a customer can act on' do
      add_inbox('one')
      add_inbox('two')

      expect { add_inbox('three') }.to raise_error(ActiveRecord::RecordInvalid, /allows up to 2 inboxes/)
      expect(account.inboxes.count).to eq(2)
    end

    it 'imposes nothing when the plan sets no inbox ceiling' do
      account.billing_subscription.update!(plan: create(:billing_plan, limits: {}))

      expect { 3.times { |i| add_inbox("free-#{i}") } }.to change(Inbox, :count).by(3)
    end

    it 'honours an operator override above the plan' do
      add_inbox('one')
      add_inbox('two')
      create(:billing_entitlement_override, account: account, kind: :limit, name: 'inboxes', limit_value: 4)

      expect { add_inbox('three') }.to change(Inbox, :count).by(1)
    end

    it 'counts only this account, so one tenant cannot exhaust another\'s allowance' do
      other = create(:account)
      3.times { |i| other.inboxes.create!(name: "other-#{i}", channel: Channel::WebWidget.create!(account: other, website_url: "https://o#{i}.example")) }

      expect { add_inbox('mine') }.to change(Inbox, :count).by(1)
    end
  end

  describe 'the agent ceiling' do
    before { subscribe(create(:billing_plan, limits: { 'agents' => 1 })) }

    # The account already has its creating administrator, so the ceiling of 1 is already reached.
    it 'refuses a second member once the ceiling is reached' do
      create(:user, account: account, role: :administrator)

      second = AccountUser.new(account: account, user: create(:user))
      expect(second).not_to be_valid
      expect(second.errors.full_messages.join).to match(/allows up to 1 team members/)
    end

    it 'allows the member that fits' do
      expect(AccountUser.new(account: account, user: create(:user))).to be_valid
    end
  end

  describe 'the channel permission, which is not a count' do
    it 'refuses a channel type the plan does not sell, whatever the inbox count' do
      subscribe(create(:billing_plan, channel_entitlements: ['Channel::WebWidget']))

      whatsapp = build(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      inbox = Inbox.new(account: account, name: 'wa', channel: whatsapp)

      expect(inbox).not_to be_valid
      expect(inbox.errors.full_messages.join).to match(/does not include the whatsapp channel/i)
    end

    it 'allows a channel type the plan does sell' do
      subscribe(create(:billing_plan, channel_entitlements: ['Channel::WebWidget']))

      expect { add_inbox('widget') }.to change(Inbox, :count).by(1)
    end

    it 'allows every channel type for a plan that names none' do
      subscribe(create(:billing_plan, channel_entitlements: []))

      whatsapp = build(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      expect(Inbox.new(account: account, name: 'wa', channel: whatsapp)).to be_valid
    end

    it 'allows every channel type for an account with no subscription at all' do
      whatsapp = build(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      expect(Inbox.new(account: account, name: 'wa', channel: whatsapp)).to be_valid
    end

    it 'honours an operator override for a channel the plan withholds' do
      subscribe(create(:billing_plan, channel_entitlements: ['Channel::WebWidget']))
      create(:billing_entitlement_override, account: account, kind: :channel, name: 'Channel::Whatsapp', enabled: true)

      whatsapp = build(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      expect(Inbox.new(account: account.reload, name: 'wa', channel: whatsapp)).to be_valid
    end
  end

  # The guard is on create only. An existing inbox must keep working when a plan is downgraded beneath it --
  # never silently deleted, and not frozen either (docs/p11/06-rollout-compatibility.md).
  describe 'an account already over a newly lowered ceiling' do
    it 'keeps its existing inboxes and can still edit them, but cannot add another' do
      subscribe(create(:billing_plan, limits: { 'inboxes' => 3 }))
      first = add_inbox('one')
      add_inbox('two')

      account.billing_subscription.update!(plan: create(:billing_plan, limits: { 'inboxes' => 1 }))

      expect(account.inboxes.count).to eq(2)
      expect { first.update!(name: 'renamed') }.not_to raise_error
      expect { add_inbox('three') }.to raise_error(ActiveRecord::RecordInvalid, /allows up to 1 inboxes/)
    end
  end
end
