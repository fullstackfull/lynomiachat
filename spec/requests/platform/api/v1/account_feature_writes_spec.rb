require 'rails_helper'

# P-FINAL: the Platform API's `features` hash used to be a raw write to the account's feature bitmask. For a
# capability a plan sells that is a commercial decision, and Billing::FeatureSync reverted it at the next plan
# change. Commercial entitlement state has one writer now -- Billing::OverrideGrant -- whichever surface asks.
RSpec.describe 'Platform API account feature writes', type: :request do
  let(:platform_app) { create(:platform_app, name: 'Ops console') }
  let(:token) { platform_app.access_token.token }
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan, features: ['lynomia_commerce']) }

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: account)
    create(:billing_subscription, account: account, plan: plan, status: 'active')
  end

  def patch_features(features)
    patch "/platform/api/v1/accounts/#{account.id}",
          params: { features: features }, headers: { api_access_token: token }, as: :json
  end

  it 'records a capability the plan does not include as an audited override, and the sync leaves it alone' do
    patch_features(channel_email: true)

    expect(response).to have_http_status(:success)
    expect(account.reload.feature_enabled?('channel_email')).to be(true)

    override = account.billing_entitlement_overrides.sole
    expect(override).to have_attributes(kind: 'feature', name: 'channel_email', enabled: true,
                                        reason: 'Set through the Platform API by Ops console')
    # granted_by is a User reference and the actor here is a PlatformApp, so the column stays empty...
    expect(override.granted_by).to be_nil
    # ...and the audit row is where the actor is recorded, because Custom::AuditLog#user is polymorphic.
    audit = Custom::AuditLog.where(comment: Billing::OverrideGrant::AUDIT_GRANTED).sole
    expect(audit).to have_attributes(user_type: 'PlatformApp', user_id: platform_app.id, username: 'Ops console')

    Billing::FeatureSync.new(account, plan).perform
    expect(account.reload.feature_enabled?('channel_email')).to be(true)
  end

  it 'records withholding a capability the plan does include' do
    account.enable_features!('lynomia_commerce')

    patch_features(lynomia_commerce: false)

    expect(account.reload.feature_enabled?('lynomia_commerce')).to be(false)
    expect(account.billing_entitlement_overrides.sole).to have_attributes(name: 'lynomia_commerce', enabled: false)

    Billing::FeatureSync.new(account, plan).perform
    expect(account.reload.feature_enabled?('lynomia_commerce')).to be(false)
  end

  # Asking for exactly what the plan already gives is not an exception, so no row is kept for it -- and an
  # earlier exception that said otherwise is revoked rather than left to contradict the plan.
  it 'revokes an override when the caller asks for what the plan already gives' do
    patch_features(lynomia_commerce: false)
    expect(account.billing_entitlement_overrides.count).to eq(1)

    patch_features(lynomia_commerce: true)

    expect(account.billing_entitlement_overrides).to be_empty
    expect(account.reload.feature_enabled?('lynomia_commerce')).to be(true)
    expect(Custom::AuditLog.where(comment: Billing::OverrideGrant::AUDIT_REVOKED).count).to eq(1)
  end

  # A capability no plan can sell is not a commercial question, so it keeps the direct write it always had.
  it 'writes a capability a plan cannot sell directly, with no override row' do
    patch_features(chatwoot_v4: true)

    expect(account.reload.feature_enabled?('chatwoot_v4')).to be(true)
    expect(account.billing_entitlement_overrides).to be_empty
  end
end
