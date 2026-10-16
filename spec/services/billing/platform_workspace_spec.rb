require 'rails_helper'

# P6D. THE INSTALLATION'S OWN WORKSPACE, AND THE WALL AROUND IT.
#
# The approved commercial model is a separate PAID subscription funded by Store Syria: not a
# comp, not a permanently free account, not an exemption from billing. What these examples
# protect is the isolation in both directions -- a merchant must not reach the platform
# workspace, the platform workspace must not appear among the customers, and neither side's
# sending may consume the other's allowance.
RSpec.describe Billing::PlatformWorkspace, type: :model do
  let(:plan) do
    create(:billing_plan, name: 'Platform operations', active: false, stripe_price_id: nil,
                          limits: { 'campaign_sends' => 5000 })
  end

  def provision(name: 'Store Syria Platform')
    described_class.provision!(name: name, plan: plan)
  end

  describe 'provisioning' do
    it 'creates a platform-owned account on a real paid subscription' do
      account = provision

      expect(account).to be_platform_owned
      expect(account.billing_subscription.status).to eq('active')
      expect(account.billing_subscription.plan).to eq(plan)
    end

    # Phase 6 is restricted from creating real charges, and this is the right default anyway:
    # an operator arranges the commercial relationship and this records it.
    it 'initiates no payment and carries no stripe id' do
      subscription = provision.billing_subscription

      expect(subscription.source).to eq('manual')
      expect(subscription.stripe_subscription_id).to be_nil
    end

    it 'refuses a second one' do
      provision

      expect { provision(name: 'Another') }.to raise_error(described_class::Refused, /already exists/)
    end

    # A plan that is active AND priced appears in every merchant's upgrade list.
    it 'refuses a plan a merchant could be sold' do
      sellable = create(:billing_plan, active: true, stripe_price_id: 'price_123',
                                       limits: { 'campaign_sends' => 10 })

      expect { described_class.provision!(name: 'X', plan: sellable) }
        .to raise_error(described_class::Refused, /sellable/)
    end

    # Entitlements returns nil when nothing sets campaign_sends, and MeteredUsage returns
    # immediately on a nil limit WITHOUT writing a counter -- unlimited, unrecorded sending,
    # which is the opposite of what this exists to provide.
    it 'refuses a plan that does not meter sending' do
      unmetered = create(:billing_plan, active: false, stripe_price_id: nil, limits: {})

      expect { described_class.provision!(name: 'X', plan: unmetered) }
        .to raise_error(described_class::Refused, /campaign_sends/)
    end
  end

  describe 'it is not a prospect' do
    # The trial starter puts an account on the merchant trial plan. A platform workspace with
    # a trialing subscription expires into a lock on a workspace nobody is going to upgrade.
    it 'is not given a merchant trial on creation' do
      allow(Billing::Settings).to receive(:enforced?).and_return(true)
      account = Account.create!(name: 'Platform', platform_owned: true)

      expect(account.reload.billing_subscription).to be_nil
    end

    # Asserted on WHICH ACCOUNTS THE SWEEP VISITS rather than on the subscription it would
    # have written: whether a trial can actually be started depends on settings this example
    # has no business configuring, and an example that passes because the machinery was
    # switched off proves nothing about the scope.
    it 'is not swept up by the trial backfill' do
      # Created BEFORE the trial is switched on, or they each get a subscription on creation
      # and the backfill -- which sweeps accounts that have none -- has nothing to visit.
      platform = Account.create!(name: 'Platform', platform_owned: true)
      merchant = Account.create!(name: 'Merchant')
      allow(Billing::TrialStarter).to receive(:configured?).and_return(true)
      visited = []
      allow(Billing::TrialStarter).to receive(:new) do |account, **|
        visited << account.id
        instance_double(Billing::TrialStarter, perform: nil)
      end

      Billing::TrialStarter.backfill!

      expect(visited).to include(merchant.id)
      expect(visited).not_to include(platform.id)
    end
  end

  describe 'it is not a customer' do
    let!(:merchant) { create(:account) }
    let!(:platform) { provision }

    it 'is absent from the operator list of accounts in trouble' do
      ids = Operations::AccountHealth.new(page: 1).call[:accounts].map(&:id)

      expect(ids).to include(merchant.id)
      expect(ids).not_to include(platform.id)
    end

    it 'is absent from what the installation reports that it sells' do
      expect(Account.tenant.count).to eq(Account.count - 1)
      expect(Account.tenant).not_to include(platform)
    end
  end

  # THE QUOTA WALL. billing_usage_counters is unique on (account_id, resource, period_start)
  # with a NOT NULL account_id, so there is no row two accounts could contend for -- the
  # isolation is structural rather than enforced by a check. These assert it holds rather
  # than assuming the schema will stay that way.
  describe 'quota isolation' do
    let!(:merchant) { create(:account) }
    let!(:platform) { provision }

    def spend(account, amount)
      amount.times { Billing::MeteredUsage.consume(account) }
    end

    it 'does not let platform sending consume a merchant allowance' do
      create(:billing_subscription, account: merchant, status: 'active', source: 'manual', plan: plan)

      spend(platform, 3)

      expect(BillingUsageCounter.where(account_id: merchant.id).sum(:used)).to eq(0)
      expect(BillingUsageCounter.where(account_id: platform.id).sum(:used)).to eq(3)
    end

    it 'does not let a merchant consume the platform allowance' do
      create(:billing_subscription, account: merchant, status: 'active', source: 'manual', plan: plan)

      spend(merchant, 2)

      expect(BillingUsageCounter.where(account_id: platform.id).sum(:used)).to eq(0)
    end
  end

  describe 'the audit trail' do
    it 'records that an operator brought the workspace into existence' do
      expect { provision }
        .to change { Custom::AuditLog.where(comment: 'billing.platform_workspace_provisioned').count }.by(1)
    end
  end
end
