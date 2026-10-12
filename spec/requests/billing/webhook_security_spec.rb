require 'rails_helper'

# P11.14 / P11.15 / P11.54 and SEC-7 of the closure sweep (docs/p11/04-subscriptions-billing.md).
#
# The endpoint used to pass `stripe_webhook_secret.to_s` to the Stripe SDK with no blank-secret guard. The SDK
# only requires a String, so an unset secret became "" and an empty HMAC key signs anything -- a signature
# anyone can reproduce. A forged event then named its own account through `client_reference_id` or
# `metadata['account_id']`, checked only with `Account.exists?`.
RSpec.describe 'Stripe billing webhook security', type: :request do
  let(:secret) { 'whsec_test_secret' }
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan, stripe_price_id: 'price_live') }

  def signed_headers(payload, with: secret, timestamp: Time.current.to_i)
    signature = OpenSSL::HMAC.hexdigest('SHA256', with, "#{timestamp}.#{payload}")
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_STRIPE_SIGNATURE' => "t=#{timestamp},v1=#{signature}" }
  end

  def subscription_event(event_id:, status: 'active', created: Time.current.to_i, account_id: account.id, subscription_id: 'sub_1')
    {
      id: event_id, object: 'event', type: 'customer.subscription.updated', created: created,
      data: { object: {
        id: subscription_id, object: 'subscription', status: status, customer: 'cus_1',
        metadata: { 'account_id' => account_id.to_s },
        cancel_at_period_end: false, current_period_end: 30.days.from_now.to_i,
        items: { data: [{ id: 'si_1', quantity: 1, current_period_end: 30.days.from_now.to_i,
                          price: { id: 'price_live', product: 'prod_1' } }] }
      } }
    }.to_json
  end

  def configure_stripe(webhook_secret: secret)
    allow(Billing::Settings).to receive(:stripe_webhook_secret).and_return(webhook_secret)
    allow(Billing::Settings).to receive(:stripe_secret_key).and_return('sk_test')
  end

  describe 'a missing webhook secret' do
    # The route is mounted unconditionally and does not consult Billing::Settings.enforced?, so this was open
    # on exactly the installations that had not finished setting billing up.
    it 'refuses the delivery instead of verifying it against an empty key' do
      configure_stripe(webhook_secret: nil)
      payload = subscription_event(event_id: 'evt_blank')

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload, with: '')

      expect(response).to have_http_status(:unauthorized)
      expect(BillingWebhookEvent.count).to eq(0)
      expect(account.reload.billing_subscription).to be_nil
    end

    it 'refuses it even when the forged signature is computed with the empty key the old code would have used' do
      configure_stripe(webhook_secret: '')
      payload = subscription_event(event_id: 'evt_empty', account_id: account.id)

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload, with: '')

      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.billing_subscription).to be_nil
    end
  end

  describe 'signature verification' do
    before { configure_stripe }

    it 'rejects a payload signed with the wrong secret' do
      payload = subscription_event(event_id: 'evt_wrong')

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload, with: 'whsec_other')

      expect(response).to have_http_status(:bad_request)
      expect(BillingWebhookEvent.count).to eq(0)
    end

    it 'rejects a payload with no signature header at all' do
      payload = subscription_event(event_id: 'evt_none')

      post '/billing/webhooks/stripe', params: payload, headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:bad_request)
    end

    it 'accepts a correctly signed event and applies it' do
      plan
      payload = subscription_event(event_id: 'evt_good')

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:ok)
      expect(account.reload.billing_subscription.status).to eq('active')
      expect(BillingWebhookEvent.find_by(provider_event_id: 'evt_good')).to be_status_processed
    end

    it 'never echoes the signing secret or the provider body in its response' do
      payload = subscription_event(event_id: 'evt_quiet')

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload, with: 'whsec_other')

      expect(response.body).not_to include(secret)
      expect(response.body).not_to include('whsec')
      expect(response.body).not_to include('cus_1')
    end
  end

  describe 'idempotency' do
    before { configure_stripe and plan }

    it 'processes a redelivered event once, however many times Stripe sends it' do
      payload = subscription_event(event_id: 'evt_repeat')

      3.times { post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload) }

      expect(response).to have_http_status(:ok)
      expect(BillingWebhookEvent.where(provider_event_id: 'evt_repeat').count).to eq(1)
    end

    it 'keeps a durable receipt an operator can read, without storing the payload' do
      payload = subscription_event(event_id: 'evt_receipt')

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload)

      receipt = BillingWebhookEvent.find_by(provider_event_id: 'evt_receipt')
      expect(receipt).to have_attributes(provider: 'stripe', event_type: 'customer.subscription.updated',
                                         account_id: account.id)
      expect(receipt.attributes.values.map(&:to_s).join).not_to include('cus_1')
    end
  end

  describe 'out-of-order delivery' do
    before { configure_stripe and plan }

    # Stripe does not guarantee order. A delayed past_due arriving after an active must not downgrade an
    # account that has already recovered.
    it 'ignores an older event that would move the subscription backwards' do
      newer = subscription_event(event_id: 'evt_newer', status: 'active', created: Time.current.to_i)
      post '/billing/webhooks/stripe', params: newer, headers: signed_headers(newer)
      expect(account.reload.billing_subscription.status).to eq('active')

      older = subscription_event(event_id: 'evt_older', status: 'past_due', created: 1.hour.ago.to_i)
      post '/billing/webhooks/stripe', params: older, headers: signed_headers(older)

      expect(account.reload.billing_subscription.status).to eq('active')
    end

    it 'applies a newer event that arrives after an older one' do
      older = subscription_event(event_id: 'evt_first', status: 'active', created: 1.hour.ago.to_i)
      post '/billing/webhooks/stripe', params: older, headers: signed_headers(older)

      newer = subscription_event(event_id: 'evt_second', status: 'past_due', created: Time.current.to_i)
      post '/billing/webhooks/stripe', params: newer, headers: signed_headers(newer)

      expect(account.reload.billing_subscription.status).to eq('past_due')
    end
  end

  describe 'tenant selection' do
    before { configure_stripe and plan }

    it 'prefers the subscription this installation already stored over the body metadata' do
      victim = create(:account)
      # Stubbing the Stripe keys makes Billing::Settings.enforced? true, and Account#start_billing_trial then
      # creates the row on commit -- so this takes the one that exists rather than adding a second, which the
      # unique index on account_id would refuse anyway.
      Billing::TrialStarter.subscription_for(account).update!(
        plan: plan, status: 'active', source: 'stripe',
        stripe_subscription_id: 'sub_known', stripe_customer_id: 'cus_1'
      )

      # The body names the victim; the stored mapping names the real owner.
      payload = subscription_event(event_id: 'evt_claim', status: 'canceled',
                                   account_id: victim.id, subscription_id: 'sub_known')
      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload)

      expect(account.reload.billing_subscription.status).to eq('canceled')
      # The victim has a subscription of its own (every account does once enforcement is on); what matters is
      # that the forged metadata did not reach it.
      expect(victim.reload.billing_subscription.stripe_subscription_id).to be_nil
      expect(victim.billing_subscription.status).not_to eq('canceled')
    end

    it 'records a verified event that matches no account as an operations signal rather than guessing' do
      payload = subscription_event(event_id: 'evt_orphan', account_id: 0, subscription_id: 'sub_unknown')

      post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:ok)
      expect(BillingWebhookEvent.find_by(provider_event_id: 'evt_orphan')).to be_status_ignored
      expect(Operations::Signal.where(source: 'billing', signal: 'unknown_provider_customer')).to exist
    end
  end
end
