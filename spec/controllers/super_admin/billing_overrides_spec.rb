require 'rails_helper'

# P11.18 / P11.26: an operator grants a commercial exception from the Super Admin page that already exists,
# and the exception is the thing the server enforces -- not a label.
RSpec.describe 'Super Admin entitlement overrides', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:plan) { create(:billing_plan, limits: { 'inboxes' => 1 }, channel_entitlements: ['Channel::Api']) }
  let(:subscription) { create(:billing_subscription, account: account, plan: plan) }

  def grant(params)
    post "/super_admin/billing_subscriptions/#{subscription.id}/grant_override", params: params
  end

  describe 'the Super Admin boundary' do
    it 'grants nothing for an unauthenticated caller' do
      grant(kind: 'feature', name: 'channel_tiktok', value: 'true', reason: 'pilot')

      expect(response).to have_http_status(:redirect)
      expect(BillingEntitlementOverride.count).to eq(0)
    end

    # A tenant administrator manages their own account; granting themselves a commercial exception is not
    # theirs to do, and there is no session that turns an account user into an operator.
    it 'grants nothing for a tenant administrator' do
      sign_in(administrator, scope: :user)
      grant(kind: 'feature', name: 'channel_tiktok', value: 'true', reason: 'pilot')

      expect(response).to have_http_status(:redirect)
      expect(BillingEntitlementOverride.count).to eq(0)
    end
  end

  context 'when signed in as a super admin' do
    # `subscription` eagerly, because the limits under test are the subscribed plan's.
    before do
      subscription
      sign_in(super_admin, scope: :super_admin)
    end

    it 'grants a feature override and audits who did it and why' do
      grant(kind: 'feature', name: 'channel_tiktok', value: 'true', reason: 'paid pilot, invoice 4471')

      override = account.billing_entitlement_overrides.sole
      expect(override).to have_attributes(kind: 'feature', name: 'channel_tiktok', enabled: true,
                                          limit_value: nil, granted_by_id: super_admin.id)

      audit = Custom::AuditLog.where(comment: Billing::OverrideGrant::AUDIT_GRANTED).sole
      expect(audit).to have_attributes(auditable_id: account.id, auditable_type: 'Account', user_id: super_admin.id)
      expect(audit.audited_changes).to include('name' => 'channel_tiktok', 'reason' => 'paid pilot, invoice 4471')
    end

    it 'refuses a grant with no reason, because an exception nobody can explain is the thing to prevent' do
      grant(kind: 'feature', name: 'channel_tiktok', value: 'true', reason: '  ')

      expect(flash[:error]).to match(/[Rr]eason/)
      expect(BillingEntitlementOverride.count).to eq(0)
    end

    it 'refuses a kind it does not have' do
      grant(kind: 'wire_transfer', name: 'anything', value: 'true', reason: 'pilot')

      expect(flash[:error]).to eq('Unknown override kind.')
      expect(BillingEntitlementOverride.count).to eq(0)
    end

    it 'refuses a limit that is not a whole number' do
      grant(kind: 'limit', name: 'inboxes', value: 'lots', reason: 'pilot')

      expect(flash[:error]).to eq('The limit must be a whole number.')
      expect(BillingEntitlementOverride.count).to eq(0)
    end

    it 'refuses an expiry in the past' do
      grant(kind: 'feature', name: 'channel_tiktok', value: 'true', reason: 'pilot', expires_at: '2020-01-01')

      expect(flash[:error]).to eq('The expiry date is not valid.')
      expect(BillingEntitlementOverride.count).to eq(0)
    end

    it 'edits the existing row when the same capability is granted again' do
      grant(kind: 'feature', name: 'channel_tiktok', value: 'true', reason: 'pilot')
      grant(kind: 'feature', name: 'channel_tiktok', value: 'false', reason: 'pilot over')

      override = account.billing_entitlement_overrides.sole
      expect(override).to have_attributes(enabled: false, reason: 'pilot over')
    end

    # The point of the whole layer: the override is what the server enforces, not a note on a page.
    # Channel::Api because that is the only channel this plan sells -- the count and the channel permission
    # are two separate rules and this example is about the count.
    it 'raises the ceiling the inbox gate actually compares' do
      api_inbox = -> { create(:inbox, account: account, channel: build(:channel_api, account: account)) }
      api_inbox.call
      expect { api_inbox.call }.to raise_error(ActiveRecord::RecordInvalid, /allows up to 1 inboxes/)

      grant(kind: 'limit', name: 'inboxes', value: '3', reason: 'migrating from a competitor')

      expect { api_inbox.call }.not_to raise_error
      expect(Billing::Entitlements.limit(account, :inboxes)).to eq(3)
    end

    # P11.5: a downgrade must never delete a customer's data. Both inbox rules are `on: :create`, so what the
    # account already has survives and only the next create is refused.
    it 'keeps inboxes the account already has when the plan stops allowing them' do
      inbox = create(:inbox, account: account, channel: build(:channel_api, account: account))
      plan.update!(limits: { 'inboxes' => 0 }, channel_entitlements: ['Channel::Whatsapp'])

      expect(inbox.reload).to be_present
      expect { inbox.update!(name: 'Renamed') }.not_to raise_error
    end

    it 'withholds a channel the plan sells' do
      expect(Billing::Entitlements.channel_allowed?(account, 'Channel::Api')).to be(true)

      grant(kind: 'channel', name: 'Channel::Api', value: 'false', reason: 'abuse investigation')

      expect(Billing::Entitlements.channel_allowed?(account, 'Channel::Api')).to be(false)
    end

    it 'revokes an override and audits the removal' do
      override = create(:billing_entitlement_override, account: account, name: 'channel_tiktok')

      post "/super_admin/billing_subscriptions/#{subscription.id}/revoke_override", params: { override_id: override.id }

      expect(BillingEntitlementOverride.exists?(override.id)).to be(false)
      audit = Custom::AuditLog.where(comment: Billing::OverrideGrant::AUDIT_REVOKED).sole
      expect(audit.audited_changes).to include('name' => 'channel_tiktok')
    end

    # Tenant isolation at the lookup itself: the id is only ever resolved inside this subscription's account.
    it 'cannot revoke another account\'s override through this subscription' do
      victim = create(:billing_entitlement_override, name: 'channel_tiktok')

      post "/super_admin/billing_subscriptions/#{subscription.id}/revoke_override", params: { override_id: victim.id }

      expect(flash[:error]).to eq('That override no longer exists.')
      expect(victim.reload).to be_present
    end

    describe 'the subscription page' do
      it 'shows the overrides, the plan\'s channels and no provider secret' do
        create(:billing_entitlement_override, account: account, kind: :limit, name: 'inboxes',
                                              enabled: nil, limit_value: 9, reason: 'migrating from a competitor')
        subscription.update!(stripe_customer_id: 'cus_9')

        get "/super_admin/billing_subscriptions/#{subscription.id}"

        expect(response.body).to include('migrating from a competitor', 'Entitlement overrides')
        expect(response.body).to include('Api') # the one channel this plan sells
        # Stripe ids identify, they do not authenticate. No secret-shaped value may reach this page (P11.56).
        expect(response.body).not_to match(/sk_(test|live)_|whsec_/)
      end
    end
  end
end
