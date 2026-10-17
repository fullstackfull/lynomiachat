# The Stripe objects this integration reads, and nothing else (docs/odoo/02-architecture.md §5).
#
# WHY IT FETCHES RATHER THAN TRUSTING A PAYLOAD. A webhook body is a snapshot of a moment that may be minutes
# old by the time a worker runs, and an accounting document must describe what the invoice IS, not what it was
# when a notification was queued. So the queue carries only the object's ID and this re-reads the authoritative
# object from Stripe. It is also why no amount, customer or account id is ever taken from the request body:
# Billing::SubscriptionSync already prefers server-owned mappings over provider metadata, for the same reason.
#
# NOTHING HERE DERIVES AN AMOUNT FROM A BillingPlan. A plan's `price` is a list price; what a customer was
# actually charged is on the Stripe invoice, after prorations, discounts, coupons and tax. The brief is explicit
# about this and it is the difference between accounting and guessing.
class Odoo::StripeSource
  class NotConfigured < StandardError; end

  def invoice(id)
    Stripe::Invoice.retrieve({ id: id, expand: ['lines'] }, options)
  end

  def charge(id)
    Stripe::Charge.retrieve(id, options)
  end

  def refund(id)
    Stripe::Refund.retrieve(id, options)
  end

  # The Lynomia account behind a Stripe customer, resolved through OUR OWN stored mapping and through nothing
  # else. A Stripe customer this installation never wrote is a customer this installation does not account
  # for, and returning nil is the right answer rather than a guess from metadata.
  def account_for_customer(stripe_customer_id)
    return nil if stripe_customer_id.blank?

    BillingSubscription.find_by(stripe_customer_id: stripe_customer_id)&.account
  end

  # The invoices to consider for a historical import, newest first, in Stripe's own order. `status: 'paid'` is
  # NOT applied: an open or uncollectible invoice is still an accounting document, and deciding which ones to
  # export is the export's job rather than the listing's.
  def invoices_in_period(from:, to:, limit: 100, starting_after: nil)
    params = { created: { gte: from.to_i, lte: to.to_i }, limit: limit, expand: ['data.lines'] }
    params[:starting_after] = starting_after if starting_after.present?
    Stripe::Invoice.list(params, options)
  end

  private

  def options
    key = Billing::Settings.stripe_secret_key.presence or raise NotConfigured, 'stripe_secret_key_missing'
    { api_key: key }
  end
end
