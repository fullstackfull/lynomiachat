require 'rails_helper'

RSpec.describe Billing::FeatureSync do
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan, features: ['lynomia_commerce']) }

  it 'applies the plan to the account\'s own feature flags' do
    described_class.new(account, plan).perform

    expect(account.reload.feature_enabled?('lynomia_commerce')).to be(true)
  end

  # P11.4. The write used to be unconditional in both directions, so an operator's deliberate enablement was
  # reverted at the next sync with nothing recording that it had been deliberate.
  it 'leaves an overridden capability alone in both directions' do
    Billing::OverrideGrant.new(account).grant!(kind: :feature, name: 'campaigns', value: true, reason: 'pilot')

    described_class.new(account, plan).perform

    # `campaigns` is not in the plan, so an unprotected sync would have switched it off.
    expect(account.reload.feature_enabled?('campaigns')).to be(true)
  end

  it 'records what it switched off, so a revert is never silent' do
    account.enable_features!('campaigns')

    described_class.new(account, plan).perform

    audit = Custom::AuditLog.where(comment: described_class::AUDIT_REVOKED_BY_SYNC).sole
    expect(audit.auditable_id).to eq(account.id)
    expect(audit.audited_changes['capabilities_disabled']).to include('campaigns')
    expect(audit.audited_changes['plan_id']).to eq(plan.id)
  end

  it 'records nothing when the account had nothing the plan withholds' do
    described_class.new(account, plan).perform

    expect(Custom::AuditLog.where(comment: described_class::AUDIT_REVOKED_BY_SYNC)).to be_empty
  end

  # A plan change whose entitlement write failed used to leave the account on its old entitlements with no
  # signal anywhere -- not Sentry, not the Operations Center.
  it 'reports a failure rather than swallowing it' do
    allow(account).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, 'accounts table is gone')
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

    expect { described_class.new(account, plan).perform }.not_to raise_error
    expect(ChatwootExceptionTracker).to have_received(:new)
    expect(Operations::Signal.where(signal: 'entitlement_sync_failed', account: account)).to exist
  end
end
