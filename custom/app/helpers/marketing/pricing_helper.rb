# The pricing page's own two readings of a BillingPlan row.
#
# A MODULE OF ITS OWN because MarketingHelper is at its line ceiling, and because these are the only two
# methods on the whole site that read the billing tables. Rails includes every helper under app/ and
# custom/app/ (config/application.rb), so nothing has to ask for it.
module Marketing::PricingHelper
  # A PLAN'S PRICE, IN ITS OWN CURRENCY, IN EITHER LANGUAGE.
  #
  # `number_to_currency(plan.price, unit: 'USD ')` was the only money formatter on the site, and under the
  # Arabic locale it printed "USD  49.00" -- rails-i18n's `ar` format is "%u %n", so a unit that already ends
  # in a space produces two. The code is a CODE, not a symbol: this installation bills in seven currencies
  # and "$49" for `sar` would be a wrong number rather than a shorter one. So the unit is the bare code and
  # the format is given here rather than taken from the locale, which also keeps both languages printing the
  # same figure in the same order -- a price is not a sentence and does not mirror.
  def marketing_plan_price(plan)
    number_to_currency(plan.price, unit: plan.currency.to_s.upcase, precision: 2, format: '%u %n',
                                   delimiter: ',', separator: '.')
  end

  # The channels a plan sells, as catalogue entries. An EMPTY `channel_entitlements` means EVERY channel --
  # the model's own rule -- and the page says so in words rather than listing ten marks that mean "no limit".
  # A channel type with no catalogue entry is dropped rather than named, which is
  # Marketing::Catalog::CHANNEL_TYPES' documented behaviour.
  def marketing_plan_channels(plan)
    Array(plan.channel_entitlements).filter_map { |type| Marketing::Catalog.channel_for_type(type) }
  end
end
