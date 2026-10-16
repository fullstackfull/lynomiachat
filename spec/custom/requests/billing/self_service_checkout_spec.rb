require 'rails_helper'

# THE PUBLIC PRICING PAGE'S ROUTE INTO THE EXISTING, AUTHORIZED CHECKOUT.
#
# The funnel crosses an authentication boundary twice: a visitor picks a plan with no identity at all, and
# finishes the purchase as an administrator of a particular account. What this file is really testing is
# that nothing is trusted across that boundary -- the plan is re-read from the database on the far side,
# the account and the role are re-checked by the endpoint that takes the money, and a caller who edits
# anything they can reach gains nothing.
#
# Stripe itself is stubbed at the SDK boundary, which is where this installation's own code ends. There is
# no Stripe key in CI and creating a real Checkout Session is Stripe's behaviour, not ours; what is ours is
# which arguments we send, whom we refuse, and what we do with the webhook that comes back -- and those are
# exercised for real below, including a genuinely signed delivery.
RSpec.describe 'Self-service checkout from the public pricing page', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: other_account, role: :administrator) }

  let(:plan) do
    create(:billing_plan, name: 'Growth', stripe_price_id: 'price_growth', active: true,
                          listed_on_website: true, price_cents: 9900)
  end

  def configure_stripe(secret: 'sk_test_x', webhook: 'whsec_test_secret')
    allow(Billing::Settings).to receive_messages(stripe_secret_key: secret, stripe_webhook_secret: webhook)
  end

  def as(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  # An account gets its billing_subscription row the moment billing is configured, and there is a unique
  # index on account_id -- so a spec that wants a paid account UPDATES that row rather than inserting a
  # second one. The index is the production guard against duplicate subscriptions; writing the specs
  # around it keeps them honest about what the schema actually allows.
  def subscribe!(**attrs)
    (account.billing_subscription || account.create_billing_subscription!).tap { |s| s.update!(**attrs) }
  end

  before { configure_stripe }

  # ---------------------------------------------------------------------------------------------------
  # Choosing a plan, with no identity yet.
  # ---------------------------------------------------------------------------------------------------
  describe 'a visitor choosing a plan' do
    it 'records the choice server-side and sends them to sign in' do
      get "/pricing/subscribe/#{plan.id}"

      expect(response).to redirect_to('/app/login')
      # The browser is given a redirect and an opaque session cookie. The plan id itself never travels.
      expect(response.headers['Location']).not_to include(plan.id.to_s)
      expect(session[Billing::PendingPlan::KEY]).to include('plan_id' => plan.id)
    end

    # Cases 7 and 8: what the operator has not put on sale cannot be bought by naming it.
    it 'refuses a plan that is not listed on the website' do
      hidden = create(:billing_plan, listed_on_website: false, active: true, stripe_price_id: 'price_hidden')

      get "/pricing/subscribe/#{hidden.id}"

      expect(response).to redirect_to(%r{/pricing#quote})
      expect(session[Billing::PendingPlan::KEY]).to be_nil
    end

    it 'refuses an inactive plan' do
      inactive = create(:billing_plan, active: false, listed_on_website: true, stripe_price_id: 'price_off')

      get "/pricing/subscribe/#{inactive.id}"

      expect(response).to redirect_to(%r{/pricing#quote})
      expect(session[Billing::PendingPlan::KEY]).to be_nil
    end

    it 'refuses a plan id that names nothing' do
      get '/pricing/subscribe/99999999'

      expect(response).to redirect_to(%r{/pricing#quote})
      expect(session[Billing::PendingPlan::KEY]).to be_nil
    end

    # Case 9: an installation with no Stripe keys cannot take money, so the page must not offer to.
    it 'refuses every plan when Stripe is not configured, and the page says so' do
      allow(Billing::Settings).to receive_messages(stripe_secret_key: nil, stripe_webhook_secret: nil)

      expect(Billing::PlanOffer.new(plan).blocker).to eq(:stripe_not_configured)

      get "/pricing/subscribe/#{plan.id}"

      expect(response).to redirect_to(%r{/pricing#quote})
      expect(session[Billing::PendingPlan::KEY]).to be_nil
    end

    # Case 12, first half: choosing twice is one intention, not two.
    it 'keeps one intention however many times it is clicked' do
      3.times { get "/pricing/subscribe/#{plan.id}" }

      expect(session[Billing::PendingPlan::KEY]).to include('plan_id' => plan.id)
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # Reading the choice back, now that there is an identity. Cases 1 and 2 -- the hop through
  # registration or sign-in is what this endpoint exists to survive, and the request spec keeps the same
  # session cookie across it exactly as a browser does.
  # ---------------------------------------------------------------------------------------------------
  describe 'reading the pending plan after signing in' do
    it 'returns the same plan and the accounts this administrator could buy it for' do
      get "/pricing/subscribe/#{plan.id}"

      as(administrator, :get, '/api/v1/billing/pending_plan')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['plan']).to include('id' => plan.id, 'name' => 'Growth')
      expect(response.parsed_body['accounts'].pluck('id')).to eq([account.id])
    end

    # Case 5, at the point where the funnel first learns the person's role. An agent is offered no account,
    # because the endpoint that takes the money would refuse them anyway.
    it 'offers an agent no account to pay from' do
      get "/pricing/subscribe/#{plan.id}"

      as(agent, :get, '/api/v1/billing/pending_plan')

      expect(response.parsed_body['plan']).to be_present
      expect(response.parsed_body['accounts']).to be_empty
    end

    it 'needs an identity' do
      get "/pricing/subscribe/#{plan.id}"
      get '/api/v1/billing/pending_plan', as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'forgets an intention older than its window' do
      get "/pricing/subscribe/#{plan.id}"

      travel_to((Billing::PendingPlan::EXPIRES_IN + 1.minute).from_now) do
        as(administrator, :get, '/api/v1/billing/pending_plan')
      end

      expect(response.parsed_body['plan']).to be_nil
    end

    # The session outlives the plan: an operator can unlist it between the click and the sign-in.
    it 'forgets a plan that has been withdrawn since it was chosen' do
      get "/pricing/subscribe/#{plan.id}"
      plan.update!(listed_on_website: false)

      as(administrator, :get, '/api/v1/billing/pending_plan')

      expect(response.parsed_body['plan']).to be_nil
    end

    it 'is cleared once the dashboard has acted on it' do
      get "/pricing/subscribe/#{plan.id}"

      as(administrator, :delete, '/api/v1/billing/pending_plan')
      expect(response).to have_http_status(:no_content)

      as(administrator, :get, '/api/v1/billing/pending_plan')
      expect(response.parsed_body['plan']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # Buying it. Case 3, and the refusals in 5 and 6.
  # ---------------------------------------------------------------------------------------------------
  describe 'the purchase itself' do
    let(:session_double) { instance_double(Stripe::Checkout::Session, url: 'https://checkout.stripe.test/c/pay/cs_test_1') }

    before do
      allow(Stripe::Customer).to receive(:create).and_return(instance_double(Stripe::Customer, id: 'cus_test_1'))
      allow(Stripe::Checkout::Session).to receive(:create).and_return(session_double)
    end

    it 'lets an administrator buy the plan they chose' do
      as(administrator, :post, "/api/v1/accounts/#{account.id}/billing/checkout", { plan_id: plan.id })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['url']).to start_with('https://checkout.stripe.test/')
      # The price Stripe is asked for is the plan's own, never a number from the caller.
      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(line_items: [hash_including(price: 'price_growth')]), anything
      )
    end

    # Case 10: the cancel URL Stripe is given is what brings an abandoned checkout back to a page that
    # says so, rather than to a dead end.
    it 'gives Stripe a cancel url that returns the customer to their subscription page' do
      as(administrator, :post, "/api/v1/accounts/#{account.id}/billing/checkout", { plan_id: plan.id })

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(cancel_url: %r{/app/accounts/#{account.id}/settings/subscription\?checkout=canceled}),
        anything
      )
    end

    it 'refuses an agent of the account' do
      as(agent, :post, "/api/v1/accounts/#{account.id}/billing/checkout", { plan_id: plan.id })

      expect(response).to have_http_status(:forbidden)
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end

    # Case 6: administering one account is not permission to spend another's money.
    it 'refuses an administrator of a different account' do
      as(outsider, :post, "/api/v1/accounts/#{account.id}/billing/checkout", { plan_id: plan.id })

      expect(response).to have_http_status(:unauthorized)
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end

    it 'refuses an inactive plan even from an administrator' do
      inactive = create(:billing_plan, active: false, stripe_price_id: 'price_off')

      as(administrator, :post, "/api/v1/accounts/#{account.id}/billing/checkout", { plan_id: inactive.id })

      expect(response).to have_http_status(:not_found)
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # Case 4 and the rest of case 12: somebody who already pays is a plan CHANGE, never a second
  # subscription.
  # ---------------------------------------------------------------------------------------------------
  describe 'an account that already has a paid subscription' do
    let(:bigger) { create(:billing_plan, stripe_price_id: 'price_scale', active: true, listed_on_website: true) }

    before do
      subscribe!(plan: plan, status: 'active', source: 'stripe',
                 stripe_subscription_id: 'sub_existing', stripe_customer_id: 'cus_existing')
      allow(Stripe::Checkout::Session).to receive(:create)
    end

    it 'refuses to open a second checkout' do
      as(administrator, :post, "/api/v1/accounts/#{account.id}/billing/checkout", { plan_id: bigger.id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/change the plan instead/i)
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end

    it 'sends them through the authorized plan-change flow instead' do
      preview = { plan_id: bigger.id, plan_name: bigger.name, amount: 50.0, currency: 'usd',
                  prorate: true, proration_date: Time.current.to_i }
      allow(Billing::PlanChange).to receive(:new)
        .and_return(instance_double(Billing::PlanChange, preview: preview))

      as(administrator, :post, "/api/v1/accounts/#{account.id}/billing/change_plan_preview", { plan_id: bigger.id })

      expect(response).to have_http_status(:success)
      # The amount to pay now is shown before anything is charged -- the confirmation step is the product's,
      # not Stripe's.
      expect(response.parsed_body).to include('amount' => 50.0, 'plan_id' => bigger.id)
    end

    it 'still refuses an agent the plan change' do
      as(agent, :post, "/api/v1/accounts/#{account.id}/billing/change_plan", { plan_id: bigger.id })

      expect(response).to have_http_status(:forbidden)
    end
  end
end
