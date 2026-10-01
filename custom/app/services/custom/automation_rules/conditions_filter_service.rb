# Audience and Commerce conditions inside Chatwoot's automation condition chain
# (docs/automation/03-audience-and-commerce-conditions.md): each becomes one more parenthesised expression joined by
# its query_operator, about the contact of the rule's conversation only (the base relation is that one conversation).
module Custom::AutomationRules::ConditionsFilterService
  def apply_filter(query_hash, current_index)
    key = query_hash['attribute_key']
    return super unless Automation::LynomiaCondition.key?(key)

    condition = Automation::LynomiaCondition.new(key, account: @account, contact_id: @conversation.contact_id)
    sql, binds = condition.to_sql(query_hash['filter_operator'], query_hash['values'], "lynomia_#{current_index}")
    @filter_values.merge!(binds)
    @query_string += " (#{sql}) #{query_hash['query_operator']} "
  end
end
