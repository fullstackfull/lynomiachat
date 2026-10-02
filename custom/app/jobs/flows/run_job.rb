# Advances one conversation's flow (docs/flow-builder/05-runtime-and-session.md) under the conversation's lock, so two
# replies arriving together, a timer and a reply, or a retried job never advance the same session twice at once. A job
# that finds the lock held waits and retries; inside it, Flows::Runner consumes each customer message at most once.
#
#   messages  message_id     new customer messages (the trigger and any after it)
#   wake      session, token a node's timer
#   human     message_id     a human reply in the bot phase
#   rejected  message_id     the channel refused a message the flow sent
#   stop                     the conversation left the bot phase
#   disabled                 the flow was disabled
class Flows::RunJob < MutexApplicationJob
  queue_as :high
  retry_on_lock_conflict wait: 1.second, attempts: 15

  MESSAGE_EVENTS = %w[messages human rejected].freeze # each given its message
  LOCK_KEY = 'LYNOMIA::FLOW::CONVERSATION::%<id>d'.freeze
  # Longer than the slowest node (a Commerce lookup waits for stores up to their 15 s timeout).
  LOCK_TIMEOUT = 60.seconds

  def perform(conversation_id, event, message_id = nil, session_id = nil, token = nil)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil?

    with_lock(format(LOCK_KEY, id: conversation_id), LOCK_TIMEOUT) do
      runner = Flows::Runner.new(conversation)
      next runner.public_send(event, conversation.messages.find_by(id: message_id)) if MESSAGE_EVENTS.include?(event)

      case event
      when 'wake' then runner.wake(session_id, token)
      when 'stop' then runner.stop
      when 'disabled' then runner.disabled
      end
    end
  end
end
