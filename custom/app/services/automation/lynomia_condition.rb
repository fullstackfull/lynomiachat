# Lynomia conditions in Chatwoot automation rules (docs/automation/03-audience-and-commerce-conditions.md), in the
# rule's own condition format and operators, for the contact of the event's conversation only:
#
#   contact_audience  equal_to "is in" / not_equal_to "is not in" one or more SHARED contact audiences of the account
#                     (personal audiences never). Membership is the audience's saved filter run for that one contact
#                     (`contacts.id = :id`), as a separate indexed query; its answer enters the rule's SQL as a bound
#                     true / false, so the audience's SQL is never pasted into the rule's.
#   commerce_*        the Audience Commerce fields (Audience::CommerceCondition): the same SQL and semantics, unknown
#                     never zero, correlated to the rule's `contacts.id`.
#   commerce_event_store, commerce_event_provider
#                     the store and platform of the Commerce event a `commerce_order_*` rule is handling
#                     (docs/automation/04-commerce-triggers.md), not the contact's links: "WHEN order shipped IF platform
#                     = Salla" is about that order. Only on Commerce triggers.
#
# Local data only: never a store call.
class Automation::LynomiaCondition
  AUDIENCE_KEY = 'contact_audience'.freeze
  AUDIENCE_OPERATORS = %w[equal_to not_equal_to].freeze
  EVENT_KEYS = %w[commerce_event_store commerce_event_provider].freeze
  MAX_VALUES = Custom::Contacts::FilterService::MAX_VALUES

  def self.key?(key) = key.to_s == AUDIENCE_KEY || event_key?(key) || Audience::CommerceCondition.field?(key.to_s)

  def self.event_key?(key) = EVENT_KEYS.include?(key.to_s)

  def initialize(key, account:, contact_id: nil)
    @key = key.to_s
    @account = account
    @contact_id = contact_id
  end

  def operators = audience? || event? ? AUDIENCE_OPERATORS : commerce_condition.operators

  # Whether the account may use the key at all: the switch, and Commerce for Commerce keys.
  def available?
    Automation::Extensions.enabled? && (audience? || @account.feature_enabled?('lynomia_commerce'))
  end

  # The values' problems for a rule of this account, as I18n keys; empty when valid.
  def errors(operator, values)
    values = Array(values)
    return ['invalid_operator'] unless operators.include?(operator)
    return ['invalid_values'] if values.size > MAX_VALUES

    return audience_errors(values) if audience?

    event? ? event_errors(values) : commerce_errors(operator, values)
  end

  # [sql, binds] for the rule's condition chain. `bind` is the condition's own bind name.
  def to_sql(operator, values, bind)
    return ['FALSE', {}] unless available?
    return event_sql(operator, values, bind) if event?
    return commerce_condition.to_sql(operator, Array(values), bind) unless audience?

    member = audiences(values).any? { |audience| member?(audience) }
    [":#{bind}", { bind => operator == 'not_equal_to' ? !member : member }]
  end

  private

  def audience? = @key == AUDIENCE_KEY

  def event? = self.class.event_key?(@key)

  # A constant for the rule's chain: the event's store or platform against the condition's values.
  def event_sql(operator, values, bind)
    data = Automation::CommerceEvents.current
    return ['FALSE', {}] if data.nil?

    actual = (@key == 'commerce_event_store' ? data[:store_id] : data[:provider]).to_s
    listed = Array(values).map(&:to_s).include?(actual)
    [":#{bind}", { bind => operator == 'not_equal_to' ? !listed : listed }]
  end

  def event_errors(values)
    return ['commerce_disabled'] unless @account.feature_enabled?('lynomia_commerce')
    return (own_stores?(values) ? [] : ['invalid_store']) if @key == 'commerce_event_store'

    values.present? && values.all? { |value| Commerce::Providers::REGISTRY.key?(value.to_s) } ? [] : ['invalid_values']
  end

  def commerce_condition = @commerce_condition ||= Audience::CommerceCondition.new(@key, account: @account)

  def audience_errors(values)
    ids = integer_ids(values)
    return ['invalid_values'] if ids.blank?
    return ['audience_not_shared'] unless shared_audiences.where(id: ids).count == ids.uniq.size

    []
  end

  def commerce_errors(operator, values)
    return ['commerce_disabled'] unless @account.feature_enabled?('lynomia_commerce')
    return ['invalid_store'] if @key == 'commerce_store' && %w[equal_to not_equal_to].include?(operator) && !own_stores?(values)

    commerce_condition.to_sql(operator, values, 'lynomia_check')
    []
  rescue CustomExceptions::CustomFilter::InvalidValue
    ['invalid_values']
  end

  def own_stores?(values)
    ids = integer_ids(values)
    ids.present? && @account.commerce_stores.where(id: ids).count == ids.uniq.size
  end

  def audiences(values)
    ids = integer_ids(values)
    found = ids.present? ? shared_audiences.where(id: ids).to_a : []
    raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: AUDIENCE_KEY) unless found.size == ids&.uniq&.size

    found
  end

  def shared_audiences = @account.custom_filters.contact.where(shared: true)

  # The audience's saved filter, for the event's contact only, as the account (no member's inbox scope).
  def member?(audience) = audience.members.exists?(id: @contact_id)

  def integer_ids(values)
    values.map { |value| Integer(value.to_s, 10) }
  rescue ArgumentError, TypeError
    nil
  end
end
