# Audience and Commerce conditions inside Chatwoot's automation condition chain
# (docs/automation/03-audience-and-commerce-conditions.md): each becomes one more parenthesised expression joined by
# its query_operator, about the contact of the rule's conversation only (the base relation is that one conversation).
module Custom::AutomationRules::ConditionsFilterService
  # Rules with Lynomia conditions on Chatwoot's own triggers leave one log line per evaluation (Automation::ExecutionLog);
  # Commerce triggers log from the listener, which knows the event.
  def perform
    lynomia = @rule.conditions.any? { |condition| Automation::LynomiaCondition.key?(condition['attribute_key']) }
    return super if !lynomia || Automation::CommerceEvents.event?(@rule.event_name) || @rule.new_record?

    started_at = Automation::ExecutionLog.clock
    super.tap do |matched|
      Automation::ExecutionLog.write(@rule, @rule.event_name, matched ? 'matched' : 'skipped', "conversation:#{@conversation.id}",
                                     started_at: started_at)
    end
  end

  # A rule that is never saved (a flow's conditions, docs/flow-builder/04-node-contracts.md) has no reauthorization
  # counter to raise: an invalid condition simply does not match.
  def rule_valid?
    return super if @rule.persisted?

    AutomationRules::ConditionValidationService.new(@rule).perform
  end

  def apply_filter(query_hash, current_index)
    key = query_hash['attribute_key']
    return super unless Automation::LynomiaCondition.key?(key)

    condition = Automation::LynomiaCondition.new(key, account: @account, contact_id: @conversation.contact_id)
    sql, binds = condition.to_sql(query_hash['filter_operator'], query_hash['values'], "lynomia_#{current_index}")
    @filter_values.merge!(binds)
    @query_string += " (#{sql}) #{query_hash['query_operator']} "
  end
end
