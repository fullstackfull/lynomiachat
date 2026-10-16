require 'rails_helper'

# WHAT HAPPENS AFTER THE CUSTOMER PAYS.
#
# The purchase is finished by Stripe, not by us, and the only thing that tells this installation about it
# is a webhook. So the question this file answers is the one the funnel actually rests on: does a
# completed Checkout Session turn into an active subscription on the right account, and does a redelivery
# of that same event leave it alone.
#
# The DELIVERY IS REAL. The payload is signed with a webhook secret the way Stripe signs one, and the
# request goes through Billing::WebhooksController, Stripe::Webhook.construct_event,
# Billing::WebhookHandler and Billing::SubscriptionSync exactly as a live delivery would. What is stubbed
# is `Stripe::Subscription.retrieve` -- the one call that leaves this machine -- because there is no Stripe
# account to retrieve from. Everything downstream of it is this installation's own code and is exercised.
RSpec.describe 'Checkout completion through the Stripe webhook', type: :request do
  let(:secret) { 'whsec_test_secret' }
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan, stripe_price_id: 'price_growth', active: true, listed_on_website: true) }

  before do
    allow(Billing::Settings).to receive_messages(stripe_webhook_secret: secret, stripe_secret_key: 'sk_test_x')
    # The customer row Checkout was opened against. Updated rather than created: an account already has
    # exactly one billing_subscription (unique index on account_id), which is itself the production guard
    # against a second subscription ever appearing.
    (account.billing_subscription || account.create_billing_subscription!)
      .update!(plan: plan, status: 'inactive', source: 'stripe', stripe_customer_id: 'cus_paid')
  end

  # Signed the way Stripe signs: HMAC-SHA256 over "<timestamp>.<payload>" with the endpoint secret.
  def signed_headers(payload, timestamp: Time.current.to_i)
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload}")
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_STRIPE_SIGNATURE' => "t=#{timestamp},v1=#{signature}" }
  end

  def checkout_completed(event_id:, subscription_id: 'sub_paid')
    {
      id: event_id, object: 'event', type: 'checkout.session.completed', created: Time.current.to_i,
      data: { object: {
        id: 'cs_test_1', object: 'checkout.session', mode: 'subscription',
        subscription: subscription_id, client_reference_id: account.id.to_s,
        metadata: { 'account_id' => account.id.to_s, 'plan_id' => plan.id.to_s }
      } }
    }.to_json
  end

  # What Stripe would hand back for that subscription id.
  def stub_retrieve(subscription_id: 'sub_paid', status: 'active')
    stripe_subscription = Stripe::Subscription.construct_from(
      id: subscription_id, object: 'subscription', status: status, customer: 'cus_paid',
      metadata: { 'account_id' => account.id.to_s, 'plan_id' => plan.id.to_s },
      cancel_at_period_end: false, current_period_end: 30.days.from_now.to_i,
      items: { data: [{ id: 'si_1', quantity: 1, current_period_end: 30.days.from_now.to_i,
                        price: { id: 'price_growth', product: 'prod_1' } }] }
    )
    allow(Stripe::Subscription).to receive(:retrieve).and_return(stripe_subscription)
  end

  it 'activates the subscription on the account that paid' do
    stub_retrieve
    payload = checkout_completed(event_id: 'evt_paid_1')

    post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload)

    expect(response).to have_http_status(:ok)
    subscription = account.reload.billing_subscription
    expect(subscription.status).to eq('active')
    expect(subscription.stripe_subscription_id).to eq('sub_paid')
    expect(subscription.plan_id).to eq(plan.id)
  end

  # Case 12. Stripe documents that it may deliver the same event more than once, and retries every
  # non-2xx. A second delivery must not produce a second subscription or a second anything.
  it 'ignores a redelivery of the same event' do
    stub_retrieve
    payload = checkout_completed(event_id: 'evt_paid_2')

    2.times { post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload) }

    expect(response).to have_http_status(:ok)
    expect(BillingSubscription.where(account_id: account.id).count).to eq(1)
    expect(BillingWebhookEvent.where(provider_event_id: 'evt_paid_2').count).to eq(1)
    # The retrieve happened once: the redelivery was dropped before any work.
    expect(Stripe::Subscription).to have_received(:retrieve).once
  end

  it 'refuses a forged delivery' do
    stub_retrieve
    payload = checkout_completed(event_id: 'evt_forged')

    post '/billing/webhooks/stripe', params: payload,
                                     headers: { 'CONTENT_TYPE' => 'application/json',
                                                'HTTP_STRIPE_SIGNATURE' => 't=1,v1=deadbeef' }

    expect(response).to have_http_status(:bad_request)
    expect(account.reload.billing_subscription.status).to eq('inactive')
  end

  # WHO THE SUBSCRIPTION BELONGS TO, and why that is safe.
  #
  # Billing::SubscriptionSync resolves the account from the session's `client_reference_id` first, then the
  # Stripe customer this installation stored, then the event's own metadata. Taking a body field first
  # looks alarming until you follow where it comes from: `client_reference_id` is written by
  # Billing::Checkout as the paying account's id, so it round-trips through Stripe rather than originating
  # with the caller, and reaching this code at all needs a signature only Stripe can produce -- which the
  # forged delivery above proves is enforced.
  #
  # This test pins both halves of that argument, because either one failing would make the other
  # insufficient.
  it 'takes the account from the session our own checkout created' do
    stub_retrieve
    payload = checkout_completed(event_id: 'evt_reference')

    post '/billing/webhooks/stripe', params: payload, headers: signed_headers(payload)

    expect(account.reload.billing_subscription.stripe_subscription_id).to eq('sub_paid')
  end

  it 'always stamps the paying account onto the session it opens' do
    buyer = create(:user, account: account, role: :administrator)
    allow(Stripe::Customer).to receive(:create).and_return(instance_double(Stripe::Customer, id: 'cus_new'))
    allow(Stripe::Checkout::Session).to receive(:create)
      .and_return(instance_double(Stripe::Checkout::Session, url: 'https://checkout.stripe.test/c/x'))
    account.billing_subscription.update!(status: 'inactive', stripe_subscription_id: nil)

    Billing::Checkout.new(account: account, plan: plan, user: buyer).perform

    # The id the webhook will later be handed is this account's, set here and nowhere else.
    expect(Stripe::Checkout::Session).to have_received(:create).with(
      hash_including(client_reference_id: account.id.to_s,
                     metadata: hash_including(account_id: account.id)), anything
    )
  end
end
