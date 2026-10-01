# The run-time check Chatwoot makes before evaluating a rule: audience and Commerce keys are known keys with their own
# operators (docs/automation/03-audience-and-commerce-conditions.md). Whether they may run now (switch, Commerce) is
# decided when they are evaluated: off, they simply do not match.
module Custom::AutomationRules::ConditionValidationService
  private

  def valid_condition?(condition)
    key = condition['attribute_key']
    return super unless Automation::LynomiaCondition.key?(key)

    Automation::LynomiaCondition.new(key, account: @account).operators.include?(condition['filter_operator'])
  end
end
