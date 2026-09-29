# frozen_string_literal: true

# Creates a Stripe Checkout Session for an account to subscribe to a plan.
# Returns the Stripe-hosted payment page URL.
#
# mobile: true -> after payment Stripe sends the customer to /mobile/billing/return,
#                 which opens the mobile app (Billing::Settings.mobile_return_url).
class Billing::Checkout
  class Error < StandardError; end

  # Stripe requires a trial_end at least 48h in the future for Checkout
  MIN_TRIAL_CARRY_OVER = 49.hours

  def initialize(account:, plan:, user:, mobile: false)
    @account = account
    @plan = plan
    @user = user
    @mobile = mobile
  end

  def perform
    raise Error, 'Stripe is not configured' unless Billing::Settings.stripe_configured?
    raise Error, 'Plan is not available' unless @plan.active? && @plan.stripe_price_id.present?

    subscription = @account.billing_subscription || @account.create_billing_subscription!
    raise Error, 'Account already has a subscription, change the plan instead' if paid_subscription?(subscription)

    ensure_customer(subscription)
    Stripe::Checkout::Session.create(session_params(subscription), opts).url
  end

  private

  def opts
    { api_key: Billing::Settings.stripe_secret_key }
  end

  def paid_subscription?(subscription)
    subscription.stripe_subscription_id.present? && subscription.status.in?(%w[active past_due])
  end

  def ensure_customer(subscription)
    return if subscription.stripe_customer_id.present?

    customer = Stripe::Customer.create(
      { email: @user.email, name: @account.name, metadata: { account_id: @account.id } },
      opts
    )
    subscription.update!(stripe_customer_id: customer.id)
  end

  def session_params(subscription)
    metadata = { account_id: @account.id, plan_id: @plan.id }
    {
      mode: 'subscription',
      customer: subscription.stripe_customer_id,
      client_reference_id: @account.id.to_s,
      line_items: [{ price: @plan.stripe_price_id, quantity: quantity }],
      success_url: return_url('success'),
      cancel_url: return_url('canceled'),
      metadata: metadata,
      subscription_data: { metadata: metadata }.merge(trial_params(subscription))
    }.merge(tax_params)
  end

  def return_url(result)
    if @mobile
      "#{base_url}/mobile/billing/return?checkout=#{result}&account_id=#{@account.id}"
    else
      "#{base_url}/app/accounts/#{@account.id}/settings/subscription?checkout=#{result}"
    end
  end

  # per_agent plans are billed per user in the account
  def quantity
    @plan.pricing_type == 'per_agent' ? [@account.users.count, 1].max : 1
  end

  # Subscribing during our trial: the first charge happens when the trial ends
  def trial_params(subscription)
    return {} unless subscription.trial_active?
    return {} if subscription.trial_ends_at < MIN_TRIAL_CARRY_OVER.from_now

    { trial_end: subscription.trial_ends_at.to_i }
  end

  def tax_params
    return {} unless Billing::Settings.stripe_tax_enabled?

    {
      automatic_tax: { enabled: true },
      billing_address_collection: 'required',
      customer_update: { address: 'auto', name: 'auto' }
    }
  end

  def base_url
    ENV.fetch('FRONTEND_URL', '').chomp('/')
  end
end
