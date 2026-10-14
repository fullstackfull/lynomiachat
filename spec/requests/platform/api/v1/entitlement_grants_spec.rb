require 'rails_helper'

# SEATS AN INTEGRATION INCLUDES WITH ITS OWN PRODUCT.
#
# A platform that bundles Lynomia into its packages must be able to say "this merchant's plan
# includes five agents" without giving them a Lynomia SUBSCRIPTION -- because a subscription is a
# second place they could be charged for seats they have already paid for once. That is the whole
# commercial point, and the first example below is the one that proves it: a ceiling, enforced,
# with no subscription anywhere.
RSpec.describe 'Integration entitlement grants', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }
  let(:account) { create(:account) }
  let(:path) { "/platform/api/v1/accounts/#{account.id}/entitlement_grants" }

  before { create(:platform_app_permissible, platform_app: platform_app, permissible: account) }

  def grant(value, resource: 'agents', ref: nil)
    put path, params: { resource: resource, limit_value: value, external_ref: ref }, headers: headers, as: :json
  end

  # The account starts with one member (its creator), so a ceiling of 1 is already reached.
  def member_count = account.reload.account_users.count

  describe 'granting' do
    it 'records the grant and reports what is now effective' do
      grant(5, ref: 'plan:growth')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('resource' => 'agents', 'limit_value' => 5,
                                              'external_ref' => 'plan:growth')
      expect(response.parsed_body['effective']).to include('limit' => 5, 'source' => 'integration')
    end

    it 'is an upsert, so a plan change replaces rather than accumulates' do
      grant(5)
      grant(9)

      expect(PlatformAppEntitlementGrant.where(account_id: account.id).count).to eq(1)
      expect(Billing::Entitlements.limit(account, :agents)).to eq(9)
    end

    it 'refuses an unknown resource and a negative value' do
      grant(5, resource: 'spaceships')
      expect(response).to have_http_status(:unprocessable_entity)

      grant(-1)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an account the app does not hold' do
      stranger = create(:account)

      put "/platform/api/v1/accounts/#{stranger.id}/entitlement_grants",
          params: { resource: 'agents', limit_value: 5 }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(PlatformAppEntitlementGrant.count).to be_zero
    end

    it 'refuses an unauthenticated caller' do
      put path, params: { resource: 'agents', limit_value: 5 }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ================================================================ the composition rules

  describe 'how the grant composes with everything else' do
    # THE COMMERCIAL POINT. No subscription, no Stripe, no second place to be charged -- and a
    # real, enforced ceiling. Without this layer an account with no subscription resolves to
    # unlimited, so seats could only be enforced by selling the merchant a Lynomia plan.
    it 'gives a real ceiling to an account with no subscription at all' do
      expect(account.billing_subscription).to be_nil
      expect(Billing::Entitlements.limit(account, :agents)).to be_nil

      grant(5)

      expect(Billing::Entitlements.limit(account, :agents)).to eq(5)
      expect(Billing::Entitlements.limit_source(account, :agents)).to eq(:integration)
    end

    # NO ADDITIVE STACKING. 10 paid + 5 included is 10, not 15.
    it 'does not add an independent plan and an included allowance together' do
      plan = create(:billing_plan, limits: { 'agents' => 10 })
      create(:billing_subscription, account: account, plan: plan, status: 'active')

      grant(5)

      expect(Billing::Entitlements.limit(account, :agents)).to eq(10)
      expect(Billing::Entitlements.limit_source(account, :agents)).to eq(:plan)
    end

    # AND NO DOWNGRADE OF PAID RIGHTS. A smaller included allowance must not reduce what the
    # merchant bought from Lynomia directly.
    it 'never lowers a ceiling the merchant pays Lynomia for' do
      plan = create(:billing_plan, limits: { 'agents' => 10 })
      create(:billing_subscription, account: account, plan: plan, status: 'active')

      grant(2)

      expect(Billing::Entitlements.limit(account, :agents)).to eq(10)
    end

    it 'raises the ceiling when the included allowance is the larger one' do
      plan = create(:billing_plan, limits: { 'agents' => 3 })
      create(:billing_subscription, account: account, plan: plan, status: 'active')

      grant(12)

      expect(Billing::Entitlements.limit(account, :agents)).to eq(12)
      expect(Billing::Entitlements.limit_source(account, :agents)).to eq(:integration)
    end

    # AN OPERATOR'S DELIBERATE DECISION IS NOT OVERRULED BY A MACHINE. This is the layer order
    # that stops an automated plan sync quietly undoing a human.
    it 'is overruled by an operator override, in both directions' do
      account.billing_entitlement_overrides.create!(kind: :limit, name: 'agents', limit_value: 2,
                                                    reason: 'abuse investigation')
      grant(50)

      expect(Billing::Entitlements.limit(account, :agents)).to eq(2)
      expect(Billing::Entitlements.limit_source(account, :agents)).to eq(:override)
    end

    it 'leaves unlimited alone when nobody grants anything' do
      expect(Billing::Entitlements.limit(account, :agents)).to be_nil
      expect(Billing::Entitlements.limit_source(account, :agents)).to eq(:default)
    end

    it 'takes the highest when two integrations both include seats' do
      other_app = create(:platform_app)
      create(:platform_app_permissible, platform_app: other_app, permissible: account)

      grant(4)
      put path, params: { resource: 'agents', limit_value: 9 },
                headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(Billing::Entitlements.limit(account, :agents)).to eq(9)
    end
  end

  # ================================================================ enforcement

  describe 'what the ceiling actually prevents' do
    # The gate is Billing::AgentLimit on AccountUser create, which every path goes through --
    # an invitation, a bulk invite, the Platform API and a reactivation. No new guard is added.
    it 'refuses a new member once the included seats are used up' do
      account.account_users.create!(user: create(:user), role: :administrator)
      grant(member_count)

      account_user = account.account_users.new(user: create(:user), role: :agent)

      expect(account_user).not_to be_valid
      expect(account_user.errors.full_messages.join).to match(/includes up to 1 team members/i)
    end

    # AND THE REFUSAL SENDS THEM TO THE RIGHT PLACE. A merchant whose seats come from their
    # Store Syria package has no Lynomia plan to upgrade; telling them to upgrade one is how a
    # clear refusal becomes a support ticket.
    it 'tells an integration-funded merchant to ask their provider, not to upgrade a plan' do
      account.account_users.create!(user: create(:user), role: :administrator)
      grant(member_count)

      account_user = account.account_users.new(user: create(:user), role: :agent)
      account_user.valid?

      expect(account_user.errors.full_messages.join).to include('Ask your provider')
      expect(account_user.errors.full_messages.join).not_to include('Upgrade your plan')
    end

    # ...and a merchant who DID buy a Lynomia plan still gets the plan wording.
    it 'still tells a plan-funded merchant to upgrade their plan' do
      plan = create(:billing_plan, limits: { 'agents' => 1 })
      create(:billing_subscription, account: account, plan: plan, status: 'active')
      account.account_users.create!(user: create(:user), role: :administrator)

      account_user = account.account_users.new(user: create(:user), role: :agent)
      account_user.valid?

      expect(account_user.errors.full_messages.join).to include('Upgrade your plan')
    end

    # "Do not allow staff to bypass seat limits through direct Lynomia APIs."
    it 'refuses a member added through the platform API too' do
      grant(member_count)
      user = create(:user)
      create(:platform_app_permissible, platform_app: platform_app, permissible: user)

      post "/platform/api/v1/accounts/#{account.id}/account_users",
           params: { user_id: user.id, role: 'agent' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.account_users.where(user_id: user.id)).to be_empty
    end

    it 'admits a member while there is room' do
      grant(member_count + 1)

      expect(account.account_users.new(user: create(:user), role: :agent)).to be_valid
    end

    # CONCURRENCY. Two invitations arriving at the last seat both read "one left" unless
    # something serializes them; Billing::ResourceLimit takes account.lock! inside the save's own
    # transaction for exactly this. Driven through real threads against real Postgres.
    it 'does not let two concurrent additions exceed the ceiling' do
      grant(member_count + 1)
      users = create_list(:user, 2)
      created = []
      mutex = Mutex.new

      users.map do |user|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ok = account.account_users.create(user: user, role: :agent).persisted?
            mutex.synchronize { created << ok }
          end
        end
      end.each(&:join)

      expect(created.count(true)).to eq(1)
      expect(account.reload.account_users.count).to eq(grant_ceiling)
    end
  end

  # ================================================================ withdrawal

  describe 'withdrawing' do
    # A DOWNGRADE MUST NOT DELETE ANYBODY. Seats in use stay; the ceiling simply stops applying.
    it 'preserves existing members and history' do
      grant(5)
      extra = create(:user)
      account.account_users.create!(user: extra, role: :agent)
      before_count = member_count

      delete path, params: { resource: 'agents' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['withdrawn']).to be(true)
      expect(member_count).to eq(before_count)
      expect(account.account_users.exists?(user_id: extra.id)).to be(true)
    end

    it 'is a no-op when nothing was granted' do
      delete path, params: { resource: 'agents' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['withdrawn']).to be(false)
    end

    it 'cannot withdraw another integration\'s grant' do
      other_app = create(:platform_app)
      create(:platform_app_permissible, platform_app: other_app, permissible: account)
      grant(5)

      delete path, params: { resource: 'agents' },
                   headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(response.parsed_body['withdrawn']).to be(false)
      expect(Billing::Entitlements.limit(account, :agents)).to eq(5)
    end
  end

  describe 'reporting' do
    it 'shows the grant, the effective ceiling, its source and the usage' do
      grant(5)

      get path, headers: headers, as: :json

      body = response.parsed_body
      expect(body['grants'].sole).to include('resource' => 'agents', 'limit_value' => 5)
      expect(body['effective']['agents']).to include('limit' => 5, 'source' => 'integration',
                                                     'used' => member_count)
    end
  end

  def grant_ceiling
    Billing::Entitlements.limit(account, :agents)
  end
end
