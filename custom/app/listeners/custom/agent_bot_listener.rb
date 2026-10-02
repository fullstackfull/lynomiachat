# Lynomia flow bots in Chatwoot's AgentBotListener (docs/flow-builder/05-runtime-and-session.md): the events webhook bots
# receive as HTTP calls, a flow bot receives as Flows::RunJob runs. Webhook bots are handled by the existing code first
# and are unchanged; a flow bot has no outgoing URL, so it never gets a webhook.
module Custom::AgentBotListener
  def message_created(event)
    super
    message = event.data[:message]
    return if message.private? || !flow_account?(message.account)

    if message.incoming?
      Flows::RunJob.perform_later(message.conversation_id, 'messages', message.id) if flow_bot?(message.inbox)
    elsif message.send(:human_response?) && live_flow?(message.conversation_id) # Chatwoot's own definition of a human reply
      Flows::RunJob.perform_later(message.conversation_id, 'human', message.id)
    end
  end

  # WhatsApp refused a message the flow sent (a template Meta rejects, a parameter it refuses): humans take over.
  def message_updated(event)
    super
    message = event.data[:message]
    return unless message.outgoing? && message.failed? && event.data[:previous_changes]&.key?('status') && flow_message?(message)

    Flows::RunJob.perform_later(message.conversation_id, 'rejected', message.id)
  end

  def conversation_status_changed(event)
    super
    conversation = event.data[:conversation]
    return if conversation.pending? || !flow_account?(conversation.account)

    Flows::RunJob.perform_later(conversation.id, 'stop') if live_flow?(conversation.id)
  end

  def conversation_updated(event)
    super
    conversation = event.data[:conversation]
    return if conversation.assignee_id.blank? || !flow_account?(conversation.account)

    Flows::RunJob.perform_later(conversation.id, 'stop') if live_flow?(conversation.id)
  end

  private

  def flow_account?(account) = account.feature_enabled?('lynomia_flow_builder')

  def flow_bot?(inbox)
    link = inbox.agent_bot_inbox
    link&.active? && link.agent_bot&.flow?
  end

  def flow_message?(message) = message.sender.is_a?(AgentBot) && message.sender.flow? && flow_account?(message.account)

  def live_flow?(conversation_id) = FlowSession.live.exists?(conversation_id: conversation_id)
end
