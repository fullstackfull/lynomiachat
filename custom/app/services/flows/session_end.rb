# How a flow session ends (docs/flow-builder/07-human-handoff.md): completed, cancelled, failed or handed off; the last two
# give the conversation to humans with Chatwoot's bot handoff. Logged and, for handoffs and failures, audited.
class Flows::SessionEnd
  def initialize(conversation)
    @conversation = conversation
  end

  def complete(session)
    close(session, :completed)
    Flows::Log.event('flow.execution.completed', session)
  end

  def cancel(session, reason)
    close(session, :cancelled, context: session.context.merge('end_reason' => reason))
    Flows::Log.event('flow.execution.cancelled', session, reason: reason)
  end

  def fail(session, code)
    close(session, :failed, failure_code: code)
    Flows::Log.event('flow.execution.failed', session, code: code)
    Flows::Audit.record('flow.execution.failed', session.agent_bot, changes: { session_id: session.id, code: code })
    hand_over
  end

  def hand_off(session, reason)
    close(session, :handed_off, context: session.context.merge('end_reason' => reason))
    Flows::Log.event('flow.execution.handoff', session, reason: reason)
    Flows::Audit.record('flow.execution.handed_off', session.agent_bot, changes: { session_id: session.id, reason: reason })
    hand_over
  end

  # No session starts (nothing published, Start does not match, flows unavailable): humans take the conversation.
  def skip(bot, reason)
    entry = { event: 'flow.start.skipped', account_id: @conversation.account_id, flow_id: bot&.id, conversation_id: @conversation.id,
              reason: reason }
    Rails.logger.info("[Lynomia::Flow] #{entry.to_json}")
    hand_over
  end

  private

  def close(session, status, **attributes)
    session.update!(status: status, finished_at: Time.current, wake_at: nil, step_token: nil, **attributes)
  end

  # Chatwoot's bot handoff: the conversation opens for humans, the bot assignee is cleared, bot reports count it.
  def hand_over
    @conversation.reload
    @conversation.bot_handoff! if @conversation.pending?
    true
  end
end
