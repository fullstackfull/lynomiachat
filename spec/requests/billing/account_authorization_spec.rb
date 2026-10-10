require 'rails_helper'

# Who may read and who may change commercial state, from the account API. The Platform API's own rule is
# covered by spec/requests/platform/api/v1/billing/authorization_spec.rb; the Super Admin boundary by
# spec/controllers/super_admin/billing_overrides_spec.rb.
RSpec.describe 'Account billing API authorization', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:plan) { create(:billing_plan, stripe_price_id: 'price_pro', limits: { 'agents' => 5 }) }

  before { create(:billing_subscription, account: account, plan: plan, status: 'active') }

  def as(user, verb, path, params = {})
    public_send(verb, "/api/v1/accounts/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
  end

  describe 'an agent of the account' do
    # Reading your own plan is not a privileged act: the dashboard shows it, and it carries no secret.
    it 'may read the plan, the catalogue and the entitlements' do
      ['billing', 'billing/plans', 'billing/entitlements'].each do |path|
        as(agent, :get, "#{account.id}/#{path}")
        expect(response).to have_http_status(:success), "expected #{path} to be readable by an agent"
      end
    end

    it 'may not spend money or change the plan' do
      [['billing/checkout', { plan_id: plan.id }],
       ['billing/portal', {}],
       ['billing/change_plan_preview', { plan_id: plan.id }],
       ['billing/change_plan', { plan_id: plan.id }]].each do |path, params|
        as(agent, :post, "#{account.id}/#{path}", params)

        expect(response).to have_http_status(:forbidden), "expected #{path} to be refused for an agent"
        expect(response.parsed_body['error']).to eq('Only administrators can manage billing')
      end
    end
  end

  describe 'a user of another account' do
    let(:outsider) { create(:user, account: other_account, role: :administrator) }

    it 'cannot read this account\'s billing state' do
      ['billing', 'billing/plans', 'billing/entitlements'].each do |path|
        as(outsider, :get, "#{account.id}/#{path}")

        expect(response).not_to have_http_status(:success), "expected #{path} to be refused cross-account"
        expect(response.body).not_to include(plan.name)
      end
    end

    it 'cannot start a checkout against this account' do
      as(outsider, :post, "#{account.id}/billing/checkout", { plan_id: plan.id })

      expect(response).not_to have_http_status(:success)
    end
  end

  describe 'an unauthenticated caller' do
    it 'reaches nothing' do
      get "/api/v1/accounts/#{account.id}/billing", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # P11.56. The customer-facing API identifies the subscription by its state, never by a provider id, and
  # never carries a key. Stripe ids live only in the Super Admin console and the Platform API.
  describe 'what the response carries' do
    before do
      account.billing_subscription.update!(stripe_customer_id: 'cus_secret', stripe_subscription_id: 'sub_secret')
      allow(Billing::Settings).to receive_messages(stripe_secret_key: 'sk_test_fake', stripe_webhook_secret: 'whsec_fake')
    end

    it 'reports that a billing account exists without naming it, and carries no secret' do
      as(administrator, :get, "#{account.id}/billing")

      expect(response.parsed_body['subscription']).to include('has_billing_account' => true)
      expect(response.body).not_to include('cus_secret', 'sub_secret', 'sk_test_fake', 'whsec_fake')
    end

    it 'carries no secret in the entitlements either' do
      as(administrator, :get, "#{account.id}/billing/entitlements")

      expect(response.body).not_to match(/sk_(test|live)_|whsec_|cus_|sub_/)
    end
  end
end
