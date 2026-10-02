# One advance of a flow session, inside the conversation's lock: what node executors may read and use. `sends` counts the
# messages sent since the session last waited (Flows::Runner::MAX_AUTO_SENDS).
class Flows::Run
  attr_reader :session, :conversation, :bot, :version
  attr_accessor :sends

  def initialize(session)
    @session = session
    @conversation = session.conversation
    @bot = session.agent_bot
    @version = session.flow_version
    @sends = 0
  end

  def account = @conversation.account

  def contact = @conversation.contact

  def context = @session.context

  def remember(key, value)
    @session.context = context.merge('values' => context.fetch('values', {}).merge(key => value.to_s.first(Flows::Variables::MAX_VALUE)))
  end

  def counter(kind, node_id)
    counts = context.fetch(kind, {})
    @session.context = context.merge(kind => counts.merge(node_id => counts.fetch(node_id, 0) + 1))
    @session.context.dig(kind, node_id)
  end

  def reset_counter(kind, node_id)
    @session.context = context.merge(kind => context.fetch(kind, {}).except(node_id))
  end

  # A message from the bot, through Chatwoot's normal path (Message callbacks → SendReplyJob → the channel), with the
  # run's `flow.*` values filled in; Chatwoot's own `{{contact.*}}` variables are rendered by the message itself.
  def say(text, content_type: :text, content_attributes: {})
    @sends += 1
    @conversation.messages.create!(
      message_type: :outgoing, account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, sender: @bot,
      content: Flows::Variables.render(text, context), content_type: content_type, content_attributes: content_attributes
    )
  end

  def can_reply? = @conversation.can_reply?
end
