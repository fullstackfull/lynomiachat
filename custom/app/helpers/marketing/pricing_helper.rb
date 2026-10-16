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
  #
  # DEDUPLICATED BY CATALOGUE IDENTITY, which is what stopped the card printing "SMS" twice. Entitlements
  # are CHANNEL TYPES and the catalogue sells PRODUCTS, and the two are not one-to-one: `Channel::Sms` and
  # `Channel::TwilioSms` both resolve to `:sms` (Marketing::Catalog::CHANNEL_TYPES), because a buyer is
  # choosing "SMS" and not choosing a gateway. A plan entitled to both is entitled to SMS once.
  #
  # The dedup is HERE, at the presentation boundary, and not on the column: the two types are genuinely
  # different entitlements to Billing::Entitlements, which checks a conversation's own channel type against
  # the list. Collapsing them in the database would withdraw one of them. `uniq` on the catalogue entry,
  # which is the identity the reader sees, leaves that untouched.
  def marketing_plan_channels(plan)
    Array(plan.channel_entitlements).filter_map { |type| Marketing::Catalog.channel_for_type(type) }.uniq(&:id)
  end

  # Every channel any listed plan could sell -- the channel rows of the comparison table. The catalogue's
  # own order, so the table reads the same way as the channel pages do.
  def marketing_comparison_channels(plans)
    sold = plans.flat_map { |plan| marketing_plan_channels(plan) }.uniq(&:id)
    return sold if plans.none? { |plan| plan.channel_entitlements.blank? }

    # A plan with no entitlement list sells every channel, so the table needs a row for each of them --
    # otherwise that plan's column would be blank for channels it actually includes.
    Marketing::Catalog.channels.uniq(&:id)
  end

  # Does this plan sell this catalogue channel? Mirrors BillingPlan#channel_included?, including its rule
  # that an empty list denies nothing, but asks the question in the catalogue's terms rather than the
  # column's -- so a plan entitled to either SMS type answers yes for the one SMS row.
  def marketing_plan_sells_channel?(plan, channel)
    return true if plan.channel_entitlements.blank?

    marketing_plan_channels(plan).any? { |sold| sold.id == channel.id }
  end

  # A limit as the reader should see it: the number, or "Unlimited" when the key is absent, which is the
  # model's meaning for a missing key (BillingPlan#limit_for).
  def marketing_plan_limit(plan, key)
    value = plan.limits[key.to_s]
    value.presence || t('marketing.pricing.unlimited')
  end
end
