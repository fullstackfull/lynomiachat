# Stripe's minor units into the major units Odoo wants (docs/odoo/05-limitations.md §amounts).
#
# WHY THIS IS NOT `amount / 100.0`. Stripe charges in a currency's smallest unit, and not every currency has
# two decimal places. Dividing by 100 is wrong for JPY (zero decimals, so 1000 means ¥1000, not ¥10) and wrong
# for KWD, BHD, JOD, OMR and TND (three decimals, so 1000 means 1.000 dinar, not 10). Kuwait matters here:
# this installation's own operator bills in KWD, and the off-by-ten-or-a-hundred would be in every invoice.
#
# The two lists are Stripe's own published ones. A currency on neither list has two decimals, which is the
# overwhelming majority, so the default is the safe one.
module Odoo::Money
  # Stripe's zero-decimal currencies: the amount IS the number of units.
  ZERO_DECIMAL = %w[bif clp djf gnf jpy kmf krw mga pyg rwf ugx vnd vuv xaf xof xpf].freeze
  # Stripe's three-decimal currencies. Stripe additionally requires these amounts to be divisible by 10, which
  # is its own constraint and not ours -- the conversion is the same either way.
  THREE_DECIMAL = %w[bhd jod kwd omr tnd].freeze

  # Returns a BigDecimal, not a Float: an accounting amount that has been through binary floating point is an
  # amount that can disagree with itself. The JSON serializer renders it as a number Odoo accepts.
  def self.to_major(minor, currency)
    BigDecimal(minor.to_i) / (10**exponent(currency))
  end

  def self.exponent(currency)
    code = currency.to_s.downcase
    return 0 if ZERO_DECIMAL.include?(code)
    return 3 if THREE_DECIMAL.include?(code)

    2
  end

  # The tolerance a total comparison allows: one minor unit, to absorb a rounding difference between Stripe's
  # arithmetic and Odoo's. Anything larger is a disagreement rather than a rounding artefact.
  def self.tolerance(currency)
    BigDecimal(1) / (10**exponent(currency))
  end
end
