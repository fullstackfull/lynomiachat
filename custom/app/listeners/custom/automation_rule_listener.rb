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
    return if contact.nil? || !Automation::Extensions.enabled?

    account = contact.account
    return unless account.feature_enabled?('lynomia_commerce')

    rules = current_account_rules(event_name, account).to_a
    return if rules.empty?

    conversation = Automation::CommerceEvents.conversation_for(contact)
    return if conversation.nil?

    Automation::CommerceEvents.with(event.data) { rules.each { |rule| run_commerce_rule(rule, account, conversation, event.data) } }
  end

  def run_commerce_rule(rule, account, conversation, data)
    return unless Automation::CommerceEvents.claim(rule, data[:event_id])
    return unless ::AutomationRules::ConditionsFilterService.new(rule, conversation, {}).perform

    ::AutomationRules::ActionService.new(rule, account, conversation).perform
  end
end
