# Test Mode (docs/flow-builder/05-runtime-and-session.md §test mode): runs a flow bot's draft on the real runtime
# (Flows::Runner, the node executors, Chatwoot's message model) for a test contact in one of the account's inboxes,
# inside a database transaction that is always rolled back. Nothing is kept and nothing leaves Lynomia: Chatwoot sends a
# message to the channel only once it is committed, and while a simulation runs the runtime schedules no timer, posts no
# webhook, calls no store and broadcasts no handoff (Flows::Simulator.active?).
#
# Stateless: each call replays the tester's whole input list from the start, so the builder keeps no test state.
#
#   { text: '...' }                         a customer message
#   { text: 'Track order', reply_id: 'lfb:menu:track' }   a tap on a WhatsApp button or list row
#   { timer: true }                         the pending timer (delay, reply timeout) fires now
class Flows::Simulator
  MAX_INPUTS = 30
  STATE = :lynomia_flow_simulation

  def self.active? = !ActiveSupport::IsolatedExecutionState[STATE].nil?

  # What the runtime would have logged, kept for the tester instead (ids, node types, results).
  def self.record(entry) = ActiveSupport::IsolatedExecutionState[STATE] << entry

  def initialize(agent_bot, version, inputs)
    @bot = agent_bot
    @version = version
    @inputs = inputs
  end

  def call
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveSupport::IsolatedExecutionState[STATE] = []
      result = replay
      raise ActiveRecord::Rollback
    end
    result
  ensure
    ActiveSupport::IsolatedExecutionState[STATE] = nil
  end

  private

  def replay
    conversation = test_conversation
    runner = Flows::Runner.new(conversation, version: @version)
    @inputs.each { |input| play(runner, conversation, input) }
    session = FlowSession.where(conversation_id: conversation.id).order(:id).last
    { transcript: transcript(conversation), session: session && session_json(session), trace: ActiveSupport::IsolatedExecutionState[STATE] }
  end

  def play(runner, conversation, input)
    return fire_timer(runner, conversation) if input[:timer]

    attributes = input[:reply_id].present? ? { interactive_reply: { id: input[:reply_id], title: input[:text] } } : {}
    message = conversation.messages.create!(message_type: :incoming, account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                            sender: conversation.contact, content: input[:text], content_attributes: attributes)
    runner.messages(message)
  end

  def fire_timer(runner, conversation)
    session = FlowSession.live.find_by(conversation_id: conversation.id)
    runner.wake(session.id, session.step_token) if session&.wake_at
  end

  # An inbox of the account the flow can run in: one it is connected to, else the first WhatsApp Cloud inbox. For the length
  # of the transaction it is given to this flow and has no automatic assignment.
  def test_conversation
    inbox = @bot.inboxes.order(:id).first ||
            @bot.account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:id).find { |candidate| Flows::ChannelCapabilities.for(candidate) }
    raise Flows::Versions::Invalid, [{ code: 'no_inbox' }] if inbox.nil?

    (inbox.agent_bot_inbox || inbox.build_agent_bot_inbox).update!(agent_bot: @bot, status: :active)
    inbox.update_columns(enable_auto_assignment: false) # rubocop:disable Rails/SkipsModelValidations
    test_contact_conversation(inbox)
  end

  # A contact with a reserved (+999) number and no email, so no avatar lookup is queued for it.
  def test_contact_conversation(inbox)
    contact = @bot.account.contacts.create!(name: 'Flow test', phone_number: "+999#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}")
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    Conversation.create!(account: @bot.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def transcript(conversation)
    conversation.messages.where(message_type: %i[incoming outgoing]).order(:id).map do |message|
      { from: from(message), text: message.content, items: message.content_attributes['items'],
        list_button: message.content_attributes['list_button'], template: message.additional_attributes&.dig('template_params', 'name') }.compact
    end
  end

  def from(message)
    return 'customer' if message.incoming?

    message.private? ? 'note' : 'bot'
  end

  def session_json(session)
    session.slice(:status, :current_node_id, :failure_code, :steps_count).merge(end_reason: session.context['end_reason'],
                                                                                timer: session.wake_at.present?)
  end
end
