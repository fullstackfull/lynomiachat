# Lynomia Audience (docs/audience/02-audience-architecture.md): conversation and Commerce conditions for contact filters
# and saved segments ("audiences"), in the condition format and with the operators every contact filter already uses.
# A condition whose key is one of these fields is built here; every other key goes to the unchanged engine, and the
# conditions keep joining through the existing flat AND / OR chain.
#
# The keys are deliberately not in lib/filters/filter_keys.yml: automation rules accept any key listed there, and they do
# not evaluate these yet (docs/audience/06-automation-integration-contract.md). A contact custom attribute that happens to
# use the same key keeps its meaning, so no existing segment changes.
module Custom::Contacts::FilterService
  # Per filter: conversation and Commerce conditions are subqueries, so their number and their values are bounded.
  MAX_CONDITIONS = 10
  MAX_VALUES = 50

  def perform
    check_audience_limits
    super
  end

  # The matching contacts without counting them: an automation rule asks about one contact
  # (docs/automation/03-audience-and-commerce-conditions.md).
  def relation
    check_audience_limits
    validate_query_operator
    query_builder(@filters['contacts'])
  end

  def build_condition_query(model_filters, query_hash, current_index)
    condition = audience_condition(query_hash['attribute_key'])
    return super unless condition

    key = query_hash['attribute_key']
    operator = query_hash['filter_operator']
    unless condition.operators.include?(operator)
      raise CustomExceptions::CustomFilter::InvalidOperator.new(attribute_name: key, allowed_keys: condition.operators)
    end

    values = Array(query_hash['values'])
    if (values.empty? && %w[is_present is_not_present].exclude?(operator)) || values.size > MAX_VALUES
      raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: key)
    end

    sql, binds = condition.to_sql(operator, values, "audience_#{current_index}")
    @filter_values.merge!(binds)
    "(#{sql}) #{query_hash['query_operator']}"
  end

  private

  def check_audience_limits
    audience = Array(@params[:payload]).count { |condition| audience_condition(condition['attribute_key']) }
    raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: 'payload') if audience > MAX_CONDITIONS
  end

  def audience_condition(key)
    @audience_conditions ||= {}
    return @audience_conditions[key] if @audience_conditions.key?(key)

    @audience_conditions[key] = build_audience_condition(key.to_s)
  end

  def build_audience_condition(key)
    commerce = Audience::CommerceCondition.field?(key)
    return unless Audience::ConversationCondition::FIELDS.key?(key) || commerce
    return if @account.custom_attribute_definitions.contact_attribute.exists?(attribute_key: key)
    return Audience::ConversationCondition.new(key, account: @account, user: @user) unless commerce

    Audience::CommerceCondition.new(key, account: @account, store_id: scoped_store_id) if @account.feature_enabled?('lynomia_commerce')
  end

  # WHICH INSTALLATION'S HISTORY THE COMMERCE AGGREGATES ARE ABOUT, when the caller is asking
  # on behalf of one. Absent, they are about every counted store, which is what they have
  # always been and what an account's own contact filter still means.
  #
  # RESOLVED THROUGH THE ACCOUNT'S OWN COUNTED STORES, so an id belonging to another tenant --
  # or to a disconnected store, or to a provider this installation does not offer -- is
  # refused at the boundary with the filter's own 422 rather than quietly narrowing to
  # nothing. A silent empty audience looks like "nobody qualifies", which is the wrong answer
  # to give somebody who has just been told their campaign will reach no one.
  def scoped_store_id
    return @scoped_store_id if defined?(@scoped_store_id)

    requested = @params[:commerce_store_id].presence
    return @scoped_store_id = nil if requested.nil?

    @scoped_store_id = Audience::CommerceCondition.counted_stores(@account).where(id: requested).pick(:id) ||
                       raise(CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: 'commerce_store_id'))
  end
end
