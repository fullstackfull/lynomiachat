# frozen_string_literal: true

# A Stripe Customer Portal link for one account (docs/p11/04-subscriptions-billing.md).
#
# Both callers -- the account's own billing page and the Platform API -- built the same session inline with a
# different return URL, so one provider call lived in two controllers. It lives here instead, which is what
# makes "every Stripe API call is in custom/app/services/billing or custom/app/jobs/billing" true rather than
# nearly true. The portal is where a customer changes a card, reads invoices and cancels, and all of that
# happens on Stripe's domain: this returns a URL and nothing else.
class Billing::Portal
  class Error < StandardError; end

  def initialize(account, return_url:)
    @account = account
    @return_url = return_url
  end

  # @return [String] the hosted portal URL
  def url
    customer_id = @account.billing_subscription&.stripe_customer_id
    raise Error, 'No billing account yet' if customer_id.blank?

    Stripe::BillingPortal::Session.create(
      { customer: customer_id, return_url: @return_url },
      { api_key: Billing::Settings.stripe_secret_key }
    ).url
  end
end
