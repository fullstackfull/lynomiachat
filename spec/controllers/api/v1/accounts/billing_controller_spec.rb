require 'rails_helper'

RSpec.describe 'Account billing API', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:plan) do
    BillingPlan.create!(name: 'Commerce', stripe_price_id: 'price_commerce', features: ['lynomia_commerce'], limits: { 'agents' => 5, 'stores' => 3 })
  end

  before do
    BillingSubscription.create!(account: account, plan: plan, status: 'active', source: 'manual', quantity: 1)
    create(:commerce_store, account: account)
    create(:commerce_store, account: account, status: :disconnected, credentials: nil)
  end

  it 'shows connected Commerce stores in the usage, and which plans include Commerce' do
    get "/api/v1/accounts/#{account.id}/billing", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['usage']).to include('stores' => 1)
    plan_row = response.parsed_body['plans'].find { |row| row['id'] == plan.id }
    expect(plan_row).to include('commerce' => true, 'limits' => { 'agents' => 5, 'stores' => 3 })
  end

  it "sends the subscribed plan's limits with the subscription, also for a plan granted without a Stripe price" do
    plan.update!(stripe_price_id: nil)

    get "/api/v1/accounts/#{account.id}/billing", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['plans']).to be_empty
    expect(response.parsed_body['subscription']).to include('plan_limits' => { 'agents' => 5, 'stores' => 3 }, 'plan_commerce' => true)
  end

  it 'reports the store limit in the entitlements' do
    get "/api/v1/accounts/#{account.id}/billing/entitlements", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['limits']['stores']).to eq('used' => 1, 'limit' => 3)
  end
end
