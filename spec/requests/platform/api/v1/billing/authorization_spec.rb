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

  # A plan is shared by every tenant on it, so a write to one modifies accounts this app may never have been
  # granted: dropping `limits.agents` from 25 to 1 blocks agent creation for all of them, mid-period. Upstream's
  # own rule is that an app may create freely but may only modify what it was granted, and this applies it.
  describe 'the shared plan catalogue' do
    it 'is readable' do
      get_with_token("/platform/api/v1/billing/plans/#{plan.id}")
      expect(response).to have_http_status(:success)
    end

    it 'cannot be re-limited while an account the app was not granted is subscribed' do
      patch "/platform/api/v1/billing/plans/#{plan.id}",
            params: { plan: { limits: { agents: 1 } } }, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('non_permissible_subscribers')
      expect(plan.reload.limits).to eq({})
    end

    it 'can be edited once every subscriber is an account the app was granted' do
      other.billing_subscription.destroy!

      patch "/platform/api/v1/billing/plans/#{plan.id}",
            params: { plan: { limits: { agents: 7 } } }, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:success)
      expect(plan.reload.limits).to eq('agents' => 7)
    end

    # Provisioning a new plan affects nobody, which is the case a legitimate integration needs.
    it 'can still be created' do
      post '/platform/api/v1/billing/plans',
           params: { plan: { name: 'Provisioned', price: 5 } }, headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:created)
      expect(BillingPlan.find_by(name: 'Provisioned')).to be_present
    end
  end

  # P11.56. A Platform App token is an installation-level credential by upstream design -- PlatformController
  # exempts `create` from its permissible check, and Platform::Api::V1::AccountsController#create makes new
  # accounts installation-wide. But a credential that can REPLACE the installation's Stripe keys is a different
  # thing: a new secret key points this installation's customers at another Stripe account, and a new webhook
  # secret both breaks every genuine delivery and re-opens the forged-event path SEC-7 closed.
  describe 'the installation Stripe credentials' do
    before { Billing::Settings.update!(stripe_secret_key: 'sk_test_original', stripe_webhook_secret: 'whsec_original') }

    it 'are not readable, not even as a masked hint' do
      get_with_token('/platform/api/v1/billing/settings')

      expect(response).to have_http_status(:success)
      body = response.parsed_body['data']
      expect(body).not_to have_key('stripe_secret_key')
      expect(body).not_to have_key('stripe_webhook_secret')
      # What an integration legitimately needs: whether billing works at all.
      expect(body).to include('stripe_configured' => true)
      expect(response.body).not_to match(/sk_test_original|whsec_original|sk_test\.\.\./)
    end

    it 'cannot be overwritten' do
      patch '/platform/api/v1/billing/settings',
            params: { settings: { stripe_secret_key: 'sk_live_attacker', stripe_webhook_secret: 'whsec_attacker' } },
            headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:success)
      expect(Billing::Settings.stripe_secret_key).to eq('sk_test_original')
      expect(Billing::Settings.stripe_webhook_secret).to eq('whsec_original')
    end

    it 'does not stop the settings it may legitimately change' do
      patch '/platform/api/v1/billing/settings',
            params: { settings: { trial_days: 21, grace_period_days: 5 } },
            headers: { api_access_token: token }, as: :json

      expect(Billing::Settings.trial_days).to eq(21)
      expect(Billing::Settings.get(:grace_period_days)).to eq(5)
    end
  end

  describe 'without a Platform App token' do
    it 'refuses the request' do
      get "/platform/api/v1/billing/subscriptions/#{granted.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
