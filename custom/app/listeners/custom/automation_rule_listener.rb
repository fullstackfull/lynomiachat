# Commerce triggers in Chatwoot's AutomationRuleListener (docs/automation/04-commerce-triggers.md): a `commerce_order_*`
# event runs the account's active rules for it, like a conversation event, on the contact's latest conversation, with
# the existing conditions and actions. Each rule runs at most once per event; Commerce rules have no delayed runs.
module Custom::AutomationRuleListener
  Automation::CommerceEvents::EVENTS.each do |event_name|
    define_method(event_name) { |event| process_commerce_event(event, event_name) }
  end

  private

  def process_commerce_event(event, event_name)
    contact = event.data[:contact]
    rules = commerce_rules(contact, event_name)
    return if rules.empty?

    conversation = Automation::CommerceEvents.conversation_for(contact)
    return rules.each { |rule| log(rule, event_name, 'no_conversation', event.data[:event_id]) } if conversation.nil?

    Automation::CommerceEvents.with(event.data) { rules.each { |rule| run_commerce_rule(rule, conversation, event.data) } }
  end

  def commerce_rules(contact, event_name)
    return [] if contact.nil? || !Automation::Extensions.enabled? || !contact.account.feature_enabled?('lynomia_commerce')

    current_account_rules(event_name, contact.account).to_a
  end

  def run_commerce_rule(rule, conversation, data)
    started_at = Automation::ExecutionLog.clock
    return log(rule, data[:event_name], 'duplicate', data[:event_id]) unless Automation::CommerceEvents.claim(rule, data[:event_id])
    unless ::AutomationRules::ConditionsFilterService.new(rule, conversation, {}).perform
      return log(rule, data[:event_name], 'skipped', data[:event_id], started_at: started_at)
    end

    ::AutomationRules::ActionService.new(rule, conversation.account, conversation).perform
    log(rule, data[:event_name], 'executed', data[:event_id], started_at: started_at, actions: rule.actions.pluck('action_name'))
  end

  def log(rule, trigger, outcome, correlation_id, details = {})
    Automation::ExecutionLog.write(rule, trigger, outcome, correlation_id, details)
  end
end
