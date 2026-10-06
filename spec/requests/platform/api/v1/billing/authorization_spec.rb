require 'rails_helper'

# The billing Platform API addresses accounts directly and can cancel or re-plan a subscription, so it follows the
# Platform API's own authorization rule: a Platform App reaches an account only when that account is one of its
# platform_app_permissibles. Before this was enforced, any Platform App token was an installation-wide billing admin.
RSpec.describe 'Billing Platform API authorization', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:token) { platform_app.access_token.token }
  let(:granted) { create(:account) }
  let(:other) { create(:account) }
  let(:plan) { BillingPlan.create!(name: 'Growth', price_cents: 1000) }

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: granted)
    BillingSubscription.create!(account: granted, plan: plan, status: 'active')
    BillingSubscription.create!(account: other, plan: plan, status: 'active')
  end

  def get_with_token(path)
    get path, headers: { api_access_token: token }, as: :json
  end

  describe 'an account the app was granted' do
    it 'is readable' do
      get_with_token("/platform/api/v1/billing/subscriptions/#{granted.id}")
      expect(response).to have_http_status(:success)
    end
  end

  describe 'an account the app was not granted' do
    it 'is not readable' do
      get_with_token("/platform/api/v1/billing/subscriptions/#{other.id}")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['message']).to eq('Non permissible resource')
    end

    it 'cannot have its subscription cancelled' do
      post "/platform/api/v1/billing/subscriptions/#{other.id}/cancel", headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(other.reload.billing_subscription.status).to eq('active')
    end

    it 'cannot be granted a plan' do
      post "/platform/api/v1/billing/subscriptions/#{other.id}/grant_plan",
           params: { plan_id: plan.id }, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'cannot have a trial extended' do
      post "/platform/api/v1/billing/subscriptions/#{other.id}/extend_trial",
           params: { days: 30 }, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'listings' do
    it 'lists only the subscriptions of granted accounts' do
      get_with_token('/platform/api/v1/billing/subscriptions')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['data'].map { |row| row.dig('account', 'id') }).to eq([granted.id])
    end

    it 'lists only granted accounts among a plan subscribers' do
      get_with_token("/platform/api/v1/billing/plans/#{plan.id}/subscribers")

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['data'].map { |row| row.dig('account', 'id') }).to eq([granted.id])
    end
  end

  describe 'without a Platform App token' do
    it 'refuses the request' do
      get "/platform/api/v1/billing/subscriptions/#{granted.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
