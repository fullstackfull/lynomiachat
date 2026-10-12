require 'rails_helper'

# P11.3 / P11.4 (docs/p11/03-plans-entitlements.md). The one service that answers "may this account do this
# right now?", and the precedence it applies.
RSpec.describe Billing::Entitlements do
  let(:account) { create(:account) }
  let(:plan) do
    create(:billing_plan, limits: { 'agents' => 3, 'inboxes' => 2 },
                          features: ['lynomia_commerce'],
                          channel_entitlements: ['Channel::WebWidget'])
  end

  def subscribe(target = account, to: plan, status: 'active')
    BillingSubscription.create!(account: target, plan: to, status: status, source: 'manual')
  end

  describe 'the default layer' do
    # This is the whole rollout-safety story: an account with no subscription behaves exactly as it does today.
    it 'imposes no limit and denies no channel for an account with no subscription' do
      expect(described_class.limit(account, :agents)).to be_nil
      expect(described_class.channel_allowed?(account, 'Channel::Whatsapp')).to be(true)
      expect(described_class.source(account, 'lynomia_commerce')).to eq(:default)
    end

    it 'denies no channel for a plan that names none, which is every plan that exists today' do
      subscribe(to: create(:billing_plan, channel_entitlements: []))

      expect(described_class.channel_allowed?(account, 'Channel::Whatsapp')).to be(true)
      expect(described_class.channel_allowed?(account, 'Channel::Api')).to be(true)
    end
  end

  describe 'the plan layer' do
    before { subscribe }

    it 'reports the plan ceiling for a counted resource' do
      expect(described_class.limit(account, :agents)).to eq(3)
      expect(described_class.limit(account, :inboxes)).to eq(2)
    end

    it 'treats an unlisted resource as unlimited rather than as zero' do
      expect(described_class.limit(account, :stores)).to be_nil
    end

    it 'allows only the channels the plan names, once it names any' do
      expect(described_class.channel_allowed?(account, 'Channel::WebWidget')).to be(true)
      expect(described_class.channel_allowed?(account, 'Channel::Whatsapp')).to be(false)
    end

    it 'attributes a plan-granted capability to the plan' do
      expect(described_class.source(account, 'lynomia_commerce')).to eq(:plan)
    end

    it 'sells nothing from a subscription that is not usable' do
      account.billing_subscription.update!(status: 'canceled')
      allow(Billing::Settings).to receive(:enforced?).and_return(true)

      expect(described_class.limit(account.reload, :agents)).to be_nil
      expect(described_class.channel_allowed?(account, 'Channel::WebWidget')).to be(true)
    end
  end

  describe 'the override layer' do
    before { subscribe }

    it 'lets an operator grant a channel the plan withholds' do
      create(:billing_entitlement_override, account: account, kind: :channel,
                                            name: 'Channel::Whatsapp', enabled: true)

      expect(described_class.channel_allowed?(account.reload, 'Channel::Whatsapp')).to be(true)
    end

    it 'lets an operator withhold a channel the plan sells' do
      create(:billing_entitlement_override, account: account, kind: :channel,
                                            name: 'Channel::WebWidget', enabled: false)

      expect(described_class.channel_allowed?(account.reload, 'Channel::WebWidget')).to be(false)
    end

    it 'lets an operator raise a ceiling' do
      create(:billing_entitlement_override, account: account, kind: :limit, name: 'agents', limit_value: 25)

      expect(described_class.limit(account.reload, :agents)).to eq(25)
    end

    it 'lets an operator lower a ceiling, including to zero' do
      create(:billing_entitlement_override, account: account, kind: :limit, name: 'inboxes', limit_value: 0)

      expect(described_class.limit(account.reload, :inboxes)).to eq(0)
    end

    it 'attributes an overridden capability to the override, which is the question the flags cannot answer' do
      create(:billing_entitlement_override, account: account, kind: :feature,
                                            name: 'lynomia_commerce', enabled: true)

      expect(described_class.source(account.reload, 'lynomia_commerce')).to eq(:override)
    end

    it 'ignores an override that has lapsed and falls back to the plan' do
      create(:billing_entitlement_override, account: account, kind: :channel, name: 'Channel::Whatsapp',
                                            enabled: true, expires_at: 1.hour.ago)

      expect(described_class.channel_allowed?(account.reload, 'Channel::Whatsapp')).to be(false)
    end

    it 'honours an override that has not lapsed yet' do
      create(:billing_entitlement_override, account: account, kind: :channel, name: 'Channel::Whatsapp',
                                            enabled: true, expires_at: 1.hour.from_now)

      expect(described_class.channel_allowed?(account.reload, 'Channel::Whatsapp')).to be(true)
    end

    it 'lists an account\'s live overrides and leaves lapsed ones out' do
      live = create(:billing_entitlement_override, account: account, kind: :feature, name: 'lynomia_commerce', enabled: true)
      create(:billing_entitlement_override, account: account, kind: :limit, name: 'agents',
                                            limit_value: 9, expires_at: 1.day.ago)

      expect(described_class.overrides(account.reload).to_a).to eq([live])
    end
  end

  describe 'the system layer' do
    before { subscribe }

    # A plan must not be able to sell or withhold the flags the product needs to function.
    it 'never treats a protected system flag as a commercial question' do
      BillingPlan::SYSTEM_FEATURES.each do |flag|
        expect(described_class.source(account, flag)).to eq(:system)
      end
    end

    it 'ignores an override that tries to reach a system flag' do
      create(:billing_entitlement_override, account: account, kind: :feature,
                                            name: BillingPlan::SYSTEM_FEATURES.first, enabled: false)
      account.enable_features!(BillingPlan::SYSTEM_FEATURES.first)

      expect(described_class.allowed?(account.reload, BillingPlan::SYSTEM_FEATURES.first)).to be(true)
    end
  end

  describe 'tenant isolation' do
    let(:other_account) { create(:account) }

    it 'does not let one account\'s override reach another' do
      subscribe
      subscribe(other_account)
      create(:billing_entitlement_override, account: other_account, kind: :channel,
                                            name: 'Channel::Whatsapp', enabled: true)

      expect(described_class.channel_allowed?(account.reload, 'Channel::Whatsapp')).to be(false)
      expect(described_class.channel_allowed?(other_account.reload, 'Channel::Whatsapp')).to be(true)
    end

    it 'answers nil rather than raising for a missing account' do
      expect(described_class.allowed?(nil, 'lynomia_commerce')).to be(false)
      expect(described_class.channel_allowed?(nil, 'Channel::Whatsapp')).to be(false)
      expect(described_class.limit(nil, :agents)).to be_nil
      expect(described_class.overrides(nil)).to be_empty
    end
  end
end
