# Real Stripe objects built from hashes, with no HTTP (custom/app/services/odoo/stripe_source.rb).
#
# `construct_from` is the Stripe gem's own deserializer, so an example gets the same object shape production
# gets -- including the nested `lines.data` and `status_transitions` accessors the exporters read. A plain
# OpenStruct would pass examples that production would fail on.
module OdooStripeObjects
  INVOICE_DEFAULTS = { id: 'in_test1', total: 14_900, currency: 'usd', customer: 'cus_test1',
                       amount_paid: 14_900, created: 1_760_000_000, paid_at: 1_760_000_100 }.freeze

  # One options hash rather than eight keywords: an example overrides the one or two fields it is about, and
  # the defaults stay in one visible place.
  def stripe_invoice(overrides = {})
    attributes = INVOICE_DEFAULTS.merge(overrides)
    lines = if overrides.key?(:lines)
              overrides[:lines]
            else
              [invoice_line(amount: attributes[:total],
                            currency: attributes[:currency])]
            end
    Stripe::Invoice.construct_from(
      id: attributes[:id], object: 'invoice', customer: attributes[:customer], currency: attributes[:currency],
      total: attributes[:total], amount_paid: attributes[:amount_paid], created: attributes[:created],
      number: 'LYN-0001', status_transitions: { paid_at: attributes[:paid_at] },
      lines: { object: 'list', data: lines }
    )
  end

  def invoice_line(amount:, currency: 'usd', description: 'Growth plan, monthly', quantity: 1)
    { id: "il_#{amount}", object: 'line_item', amount: amount, amount_excluding_tax: amount,
      currency: currency, description: description, quantity: quantity }
  end

  def stripe_refund(id: 'rf_test1', amount: 14_900, currency: 'usd', charge: 'ch_test1', created: 1_760_100_000)
    Stripe::Refund.construct_from(id: id, object: 'refund', amount: amount, currency: currency,
                                  charge: charge, created: created)
  end

  def stripe_charge(id: 'ch_test1', invoice: 'in_test1', customer: 'cus_test1', refunds: [])
    Stripe::Charge.construct_from(id: id, object: 'charge', invoice: invoice, customer: customer,
                                  refunds: { object: 'list', data: refunds })
  end
end

RSpec.configure { |config| config.include OdooStripeObjects }
