# The existing webhook action, run by a Commerce trigger (docs/automation/04-commerce-triggers.md): the payload Chatwoot
# sends (the conversation, `event: automation_event.<event>`) plus the Commerce event: store, platform, the order's
# number and normalized states. This is how n8n and other tools receive Commerce events; no separate integration.
module Custom::AutomationRules::ActionService
  private

  def send_webhook_event(webhook_url)
    data = Automation::CommerceEvents.current
    return super if data.blank?

    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}",
                                               commerce: Automation::CommerceEvents.webhook_context(data))
    WebhookJob.perform_later(webhook_url[0], payload)
  end
end
