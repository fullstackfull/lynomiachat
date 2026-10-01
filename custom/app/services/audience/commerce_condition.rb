# Lynomia Audience: Commerce conditions for contact filters and audiences (docs/audience/03-commerce-query-model.md),
# evaluated in SQL over customer links and their summaries (Commerce::ContactMetric). Never a store call.
#
# A link counts when it is not suppressed and its store is active and of a provider the installation offers, the same
# stores Customer 360 reads; anything else contributes nothing (provider hard-off). Store and provider conditions are
# facts about links. Order conditions use the summaries, where a link without one is unknown, never zero:
#
#   can only grow with more data  ("more than", "after", "has an order with …"): true when the known summaries prove it
#   could change with more data   ("less than", "equal", "before", "has no order with …"): only when every counted link
#                                 of the contact is known; otherwise the contact does not match
#
# Spend is per currency, never converted: `commerce_spend_<currency>` (commerce_spend_sar).
class Audience::CommerceCondition
  FIELDS = {
    'commerce_store' => %w[equal_to not_equal_to is_present is_not_present],
    'commerce_provider' => %w[equal_to not_equal_to],
    'commerce_orders_count' => %w[equal_to is_greater_than is_less_than],
    'commerce_last_purchase_at' => %w[is_greater_than is_less_than days_before],
    'commerce_active_order' => %w[equal_to],
    'commerce_order_status' => %w[equal_to not_equal_to],
    'commerce_payment_status' => %w[equal_to not_equal_to],
    'commerce_shipment_status' => %w[equal_to not_equal_to]
  }.freeze
  SPEND_FIELD = /\Acommerce_spend_([a-z]{3})\z/
  SPEND_OPERATORS = %w[is_greater_than is_less_than].freeze
  # The normalized values (Commerce::Order).
  STATUSES = {
    'commerce_order_status' => ['order_statuses', %w[pending processing on_hold shipped delivered completed cancelled refunded failed draft other]],
    'commerce_payment_status' => ['payment_statuses', %w[paid unpaid partially_paid failed refunded partially_refunded unknown]],
    'commerce_shipment_status' => ['shipment_statuses', %w[pending in_transit out_for_delivery delivered failed cancelled returned other]]
  }.freeze

  def self.field?(key) = FIELDS.key?(key) || SPEND_FIELD.match?(key.to_s)

  # The stores whose links count: the stores Customer 360 reads.
  def self.counted_stores(account) = account.commerce_stores.active.where(provider: Commerce::Providers.enabled)

  def self.counted_links(account)
    Commerce::CustomerLink.where(account: account, commerce_store_id: counted_stores(account).select(:id)).where.not(match_source: :suppressed)
  end

  def initialize(key, account:)
    @key = key
    @account = account
  end

  def operators = FIELDS[@key] || SPEND_OPERATORS

  # SQL for the contacts query, and its bind values. `bind` is the condition's own bind name.
  def to_sql(operator, values, bind)
    @bind = bind
    @binds = { 'audience_account' => @account.id, 'audience_providers' => Commerce::Providers.enabled,
               'audience_suppressed' => Commerce::CustomerLink.match_sources[:suppressed],
               'audience_active' => Commerce::Store.statuses[:active] }
    [condition(operator, values), @binds]
  rescue ArgumentError, TypeError
    invalid!
  end

  private

  def condition(operator, values)
    case @key
    when 'commerce_store' then link_condition(operator, 'audience_stores.id', -> { ids(values) })
    when 'commerce_provider' then link_condition(operator, 'audience_stores.provider', -> { listed(values, Commerce::Providers::REGISTRY.keys) })
    when 'commerce_orders_count' then compare(operator, 'SUM(audience_metrics.orders_count)', count(values))
    when 'commerce_last_purchase_at' then purchased(operator, values)
    when 'commerce_active_order' then active_order(values)
    when *STATUSES.keys then statuses(operator, values)
    else spend(operator, values)
    end
  end

  # Every counted link of the contact, with its summary when there is one.
  def links
    'FROM commerce_customer_links audience_links ' \
      'INNER JOIN commerce_stores audience_stores ON audience_stores.id = audience_links.commerce_store_id ' \
      'LEFT JOIN commerce_contact_metrics audience_metrics ON audience_metrics.commerce_customer_link_id = audience_links.id ' \
      'WHERE audience_links.contact_id = contacts.id AND audience_links.account_id = :audience_account ' \
      'AND audience_links.match_source <> :audience_suppressed AND audience_stores.status = :audience_active ' \
      'AND audience_stores.provider IN (:audience_providers)'
  end

  def link_condition(operator, column, values)
    return "EXISTS (SELECT 1 #{links})" if operator == 'is_present'
    return "NOT EXISTS (SELECT 1 #{links})" if operator == 'is_not_present'

    @binds[@bind] = values.call
    "#{'NOT ' if operator == 'not_equal_to'}EXISTS (SELECT 1 #{links} AND #{column} IN (:#{@bind}))"
  end

  # Over the known summaries only: for conditions more data can only make true.
  def known(aggregate) = "(SELECT #{aggregate} #{links} AND audience_metrics.id IS NOT NULL)"

  # NULL unless every counted link of the contact has a summary: for conditions more data could make false.
  def complete(aggregate)
    "(SELECT CASE WHEN COUNT(*) > 0 AND COUNT(audience_metrics.id) = COUNT(*) THEN #{aggregate} END #{links})"
  end

  def compare(operator, aggregate, value)
    @binds[@bind] = value
    case operator
    when 'is_greater_than' then "#{known(aggregate)} > :#{@bind}"
    when 'is_less_than' then "#{complete(aggregate)} < :#{@bind}"
    else "#{complete(aggregate)} = :#{@bind}"
    end
  end

  def spend(operator, values)
    currency = SPEND_FIELD.match(@key)[1].upcase
    @binds["#{@bind}_currency"] = currency
    compare(operator, "SUM(COALESCE((audience_metrics.spend ->> :#{@bind}_currency)::numeric, 0))", amount(values))
  end

  def purchased(operator, values)
    @binds[@bind] = operator == 'days_before' ? Time.zone.today - days(values) : date(values)
    return "(#{known('MAX(audience_metrics.last_purchase_at)')})::date > :#{@bind}" if operator == 'is_greater_than'

    "(#{complete('MAX(audience_metrics.last_purchase_at)')})::date < :#{@bind}"
  end

  def active_order(values)
    case single(values).to_s
    when 'true' then "EXISTS (SELECT 1 #{links} AND audience_metrics.active_orders_count > 0)"
    when 'false' then "#{complete('SUM(audience_metrics.active_orders_count)')} = 0"
    else invalid!
    end
  end

  def statuses(operator, values)
    column, allowed = STATUSES.fetch(@key)
    @binds[@bind] = listed(values, allowed)
    overlap = "audience_metrics.#{column} && ARRAY[:#{@bind}]::varchar[]"
    return "EXISTS (SELECT 1 #{links} AND #{overlap})" if operator == 'equal_to'

    "#{complete("bool_and(NOT (#{overlap}))")} IS TRUE"
  end

  def ids(values) = values.map { |value| Integer(value.to_s, 10) }

  def listed(values, allowed)
    invalid! unless values.all? { |value| allowed.include?(value) }

    values
  end

  def count(values)
    Integer(single(values).to_s, 10).tap { |value| invalid! if value.negative? }
  end

  def amount(values)
    BigDecimal(single(values).to_s).tap { |value| invalid! unless value.finite? && !value.negative? }
  end

  def date(values) = Date.iso8601(single(values).to_s)

  # The UI offers 1..998 days, as for every other date filter.
  def days(values)
    Integer(single(values).to_s, 10).tap { |value| invalid! unless value.between?(1, 998) }
  end

  def single(values)
    invalid! unless values.one?

    values.first
  end

  def invalid! = raise(CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: @key))
end
