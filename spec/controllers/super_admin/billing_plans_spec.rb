require 'rails_helper'

# The Administrate wiring, which the Billing::PlanAudit service spec cannot cover: the edit form has to warn
# about the blast radius, and the update hook has to record the change with the operator who made it.
RSpec.describe 'Super Admin billing plans', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:plan) { create(:billing_plan, limits: { 'inboxes' => 5 }) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'warns on the edit form how many accounts an entitlement change will move' do
    create(:billing_subscription, plan: plan, status: 'active')
    create(:billing_subscription, plan: plan, status: 'canceled')

    get "/super_admin/billing_plans/#{plan.id}/edit"

    expect(response).to have_http_status(:success)
    # One paying account, not two: a canceled subscription is not paying for anything.
    expect(response.body).to include('<strong>1</strong> account currently pay')
    expect(response.body).to include('create a new plan and move customers to it')
  end

  it 'says nothing about a blast radius when nobody is on the plan' do
    get "/super_admin/billing_plans/#{plan.id}/edit"

    expect(response.body).not_to include('currently pay for this plan')
  end

  it 'records an entitlement change with the operator who made it' do
    create(:billing_subscription, plan: plan, status: 'active')

    patch "/super_admin/billing_plans/#{plan.id}",
          params: { billing_plan: { name: plan.name, limits: { 'inboxes' => '2' } } }

    expect(plan.reload.limits).to eq('inboxes' => 2)
    audit = Custom::AuditLog.where(comment: Billing::PlanAudit::AUDIT_EVENT).sole
    expect(audit.user_id).to eq(super_admin.id)
    expect(audit.audited_changes).to include('subscribers_affected' => 1)
  end

  it 'records nothing when the edit did not change what the plan sells' do
    patch "/super_admin/billing_plans/#{plan.id}",
          params: { billing_plan: { name: plan.name, limits: { 'inboxes' => '5' }, description: 'Nicer copy' } }

    expect(plan.reload.description).to eq('Nicer copy')
    expect(Custom::AuditLog.where(comment: Billing::PlanAudit::AUDIT_EVENT)).to be_empty
  end
end
