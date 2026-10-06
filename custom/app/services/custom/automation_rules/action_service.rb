# The existing webhook action, run by a Commerce trigger (docs/automation/04-commerce-triggers.md): the payload Chatwoot
# sends (the conversation, `event: automation_event.<event>`) plus the Commerce event: store, platform, the order's
# number and normalized states. This is how n8n and other tools receive Commerce events; no separate integration.
#
# And the approved-WhatsApp-template action (docs/pre-p7-closeout/03-template-automation-action.md). Kept as thin as
# every other action here: it resolves nothing and decides nothing, it hands the rule's configuration to
# Custom::AutomationRules::TemplateAction. Dispatch is the parent's own
# `send(action[:action_name], action[:action_params])`, so no registry or dispatcher is added.
module Custom::AutomationRules::ActionService
  private

  def send_webhook_event(webhook_url)
    data = Automation::CommerceEvents.current
    return super if data.blank?

    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}",
                                               commerce: Automation::CommerceEvents.webhook_context(data))
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  # `action_params` follows the existing convention — an array whose first element is the action's configuration, the
  # same shape `send_email_to_team` already uses. It carries an inbox id, a template name, a language and a variable
  # mapping, and never a credential: the channel's token is read from the inbox at send time by the existing sender.
  def send_whatsapp_template(params)
    Custom::AutomationRules::TemplateAction.new(
      rule: @rule, account: @account, conversation: @conversation, config: Array(params).first
    ).perform
  end
end
