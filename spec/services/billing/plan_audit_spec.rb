require 'rails_helper'

# P11.2. There is no plan_versions table, so editing a plan changes every subscriber immediately. The control
# is that such a change is never silent or unattributable.
RSpec.describe Billing::PlanAudit do
  let(:super_admin) { create(:super_admin) }
  let(:plan) { create(:billing_plan, limits: { 'inboxes' => 5 }) }

  it 'records what moved, who moved it and how many paying accounts it moved for' do
    create(:billing_subscription, plan: plan, status: 'active')
    create(:billing_subscription, plan: plan, status: 'trialing')
    create(:billing_subscription, plan: plan, status: 'canceled')

    plan.update!(limits: { 'inboxes' => 2 }, channel_entitlements: ['Channel::Api'])
    described_class.record(plan, actor: super_admin)

    audit = Custom::AuditLog.where(comment: described_class::AUDIT_EVENT).sole
    expect(audit).to have_attributes(auditable_id: plan.id, auditable_type: 'BillingPlan', user_id: super_admin.id)
    expect(audit.audited_changes['limits']).to eq([{ 'inboxes' => 5 }, { 'inboxes' => 2 }])
    expect(audit.audited_changes['channel_entitlements']).to eq([[], ['Channel::Api']])
    # A canceled subscription is not paying for anything, so it is not counted.
    expect(audit.audited_changes['subscribers_affected']).to eq(2)
  end

  it 'records nothing when the edit did not touch what the plan sells' do
    plan.update!(description: 'Nicer copy', position: 3)
    described_class.record(plan, actor: super_admin)

    expect(Custom::AuditLog.where(comment: described_class::AUDIT_EVENT)).to be_empty
  end

  # The Platform API's actor is a PlatformApp, not a User. Custom::AuditLog#user is polymorphic, but its
  # after_save read `user.email` unconditionally, which raised and rolled the row back -- so the actor with
  # the least accountability was the one whose plan edits went unrecorded.
  it 'records a Platform App as the actor' do
    platform_app = create(:platform_app, name: 'Ops console')
    plan.update!(features: ['lynomia_commerce'])

    described_class.record(plan, actor: platform_app)

    audit = Custom::AuditLog.where(comment: described_class::AUDIT_EVENT).sole
    expect(audit).to have_attributes(user_type: 'PlatformApp', user_id: platform_app.id, username: 'Ops console')
  end

  # The plan is already saved by the time this runs; a failed audit write must not look like a failed edit.
  it 'does not raise when the audit row cannot be written' do
    plan.update!(features: ['lynomia_commerce'])
    allow(Custom::AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'audits table is gone')

    expect { described_class.record(plan, actor: super_admin) }.not_to raise_error
  end
end
