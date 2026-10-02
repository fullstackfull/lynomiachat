# Advances a conversation's flow session (docs/flow-builder/05-runtime-and-session.md). Always called inside the
# conversation's lock (Flows::RunJob), so one conversation is advanced by one worker at a time.
#
# The flow owns a conversation only in Chatwoot's bot phase: its inbox's active bot is this flow bot, the conversation is
# pending, no human is assigned. Outside it the flow does nothing, and a live session is cancelled.
#
#   messages(trigger)   new customer messages, oldest first, each consumed at most once (last_message_id): the first
#                       starts a session (Start keywords / conditions, else the conversation goes to humans); later ones
#                       answer the node the session waits at
#   wake(id, token)     a node's timer (delay, reply timeout); a stale token is ignored
#   human(message)      a human replied (agent, or the WhatsApp Business app on a coexistence number): handed off
#   stop                the conversation left the bot phase (resolved, opened, assigned): the session is cancelled
#   disabled            the flow was disabled: live sessions are handed to humans
#
# Safety limits: MAX_AUTO_STEPS nodes between two waits, MAX_NODE_VISITS visits of one node, MAX_SESSION_STEPS nodes in a
# session, MAX_AUTO_SENDS messages between two waits. Crossing one fails the session and hands the conversation over.
class Flows::Runner
  MAX_AUTO_STEPS = 25
  MAX_NODE_VISITS = 10
  MAX_SESSION_STEPS = 200
  MAX_AUTO_SENDS = 5
  MAX_MESSAGES_PER_RUN = 10

  def initialize(conversation)
    @conversation = conversation
  end

  def messages(trigger)
    return if bot.nil? || trigger.nil? || trigger.conversation_id != @conversation.id

    session = live_session
    return stop(session, 'left_bot_phase') unless bot_phase?
    return unavailable(session) unless runnable?

    consume(trigger, session)
  end

  def wake(session_id, token)
    session = timer_session(session_id, token)
    return if session.nil?
    return stop(session, 'left_bot_phase') unless bot_phase? && session.agent_bot_id == bot&.id
    return unavailable(session) unless runnable?

    Flows::Log.event('flow.wait.resumed', session, by: 'timer')
    run = Flows::Run.new(session)
    node = run.version.node(session.current_node_id)
    continue(run, node, Flows::Nodes.for(run, node).wake)
  end

  def human(message)
    session = live_session
    return if session.nil? || message.nil? || !message.send(:human_response?) # Chatwoot's own definition of a human reply

    hand_off(session, 'human_reply')
  end

  # The flow was disabled (Flows::Versions#disable!): humans take its live conversations.
  def disabled
    session = live_session
    hand_off(session, 'flow_disabled') if session
  end

  def stop(session = live_session, reason = 'left_bot_phase')
    ending.cancel(session, reason) if session
  end

  private

  def bot
    @bot ||= begin
      link = @conversation.inbox.agent_bot_inbox
      link.agent_bot if link&.active? && link.agent_bot&.flow?
    end
  end

  def bot_phase?
    bot.present? && @conversation.pending? && @conversation.assignee_id.nil? &&
      [nil, bot].include?(@conversation.ai_assignee)
  end

  def runnable?
    Flows::Switch.available?(@conversation.account) && @conversation.contact.present? && !@conversation.contact.blocked?
  end

  def live_session = FlowSession.live.find_by(conversation_id: @conversation.id)

  def timer_session(id, token)
    session = FlowSession.find_by(id: id, conversation_id: @conversation.id)
    session if session&.waiting? && token.present? && session.step_token == token
  end

  def consume(trigger, session)
    unconsumed(trigger, session).each do |message|
      current = live_session
      current ? reply(current, message) : start(message)
      break if live_session.nil? && !bot_phase?
    end
  end

  # Incoming customer messages not consumed yet, oldest first. Without a live session a new one starts at the trigger.
  def unconsumed(trigger, session)
    after = FlowSession.where(conversation_id: @conversation.id).maximum(:last_message_id).to_i
    scope = @conversation.messages.incoming.where(private: false).where('messages.id > ?', after)
    scope = scope.where('messages.id >= ?', trigger.id) if session.nil?
    scope.order(:id).limit(MAX_MESSAGES_PER_RUN).to_a
  end

  def start(message)
    version = bot.published_flow_version
    return hand_off_conversation('no_published_version') if version.nil?

    node = version.nodes.find { |candidate| candidate['type'] == 'start' }
    unless Flows::Nodes::Start.keywords_match?(node, message.content) && Flows::Nodes::Start.conditions_match?(node, @conversation)
      return hand_off_conversation('start_not_matched')
    end

    session = FlowSession.create!(account: @conversation.account, agent_bot: bot, flow_version: version, conversation: @conversation,
                                  status: :active, current_node_id: node['id'], last_message_id: message.id,
                                  context: { 'reply' => message.content.to_s.first(Flows::Variables::MAX_VALUE) })
    Flows::Log.event('flow.execution.started', session)
    advance(Flows::Run.new(session), node)
  end

  def reply(session, message)
    session.update!(last_message_id: message.id, context: session.context.merge('reply' => message.content.to_s.first(Flows::Variables::MAX_VALUE)))
    # A session left active was interrupted mid-run (a worker stopped): it cannot resume safely.
    return fail(Flows::Run.new(session), 'interrupted') if session.active?

    Flows::Log.event('flow.wait.resumed', session, by: 'reply')
    run = Flows::Run.new(session)
    node = run.version.node(session.current_node_id)
    continue(run, node, Flows::Nodes.for(run, node).reply(message))
  end

  def continue(run, node, step)
    next_node = after(run, node, step)
    advance(run, next_node) if next_node
  end

  # Runs nodes from `node` until one waits or the session ends.
  def advance(run, node)
    steps = 0
    while node
      return fail(run, limit_code(run, node, steps)) if limit_code(run, node, steps)

      steps += 1
      node = execute(run, node)
    end
  end

  def limit_code(run, node, steps)
    return 'step_limit' if steps >= MAX_AUTO_STEPS || run.session.steps_count >= MAX_SESSION_STEPS
    return 'send_limit' if run.sends > MAX_AUTO_SENDS

    'visit_limit' if run.context.dig('visits', node['id']).to_i >= MAX_NODE_VISITS
  end

  def execute(run, node)
    started = Flows::Log.clock
    run.counter('visits', node['id'])
    step = Flows::Nodes.for(run, node).enter
    run.session.steps_count += 1
    Flows::Log.event('flow.node.executed', run.session, node_id: node['id'], node_type: node['type'],
                                                        result: (step.output || step.status || step.kind).to_s, duration_ms: Flows::Log.ms(started))
    after(run, node, step)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: run.account).capture_exception
    fail(run, 'node_error')
    nil
  end

  # The node a step leads to, or nil when the session waits or ended.
  def after(run, node, step)
    case step.kind
    when :wait then wait(run, node, step.wake_at)
    when :finish then step.status == :failed ? fail(run, step.code) : finish(run, step.status, step.code)
    else follow(run, node, step.output)
    end
  end

  def follow(run, node, output)
    edge = run.version.edges.find { |candidate| candidate['source'] == node['id'] && candidate['sourceHandle'] == output }
    return run.version.node(edge['target']) if edge
    return run.version.node(node.dig('data', 'target')) if node['type'] == 'goto'

    hand_off(run.session, "unrouted_#{output}")
    nil
  end

  def wait(run, node, wake_at)
    @conversation.reload
    return hand_off(run.session, 'human_assigned') && nil unless bot_phase?

    token = SecureRandom.hex(8)
    run.session.update!(status: :waiting, current_node_id: node['id'], wake_at: wake_at, step_token: token)
    Flows::RunJob.set(wait_until: wake_at).perform_later(@conversation.id, 'wake', nil, run.session.id, token) if wake_at
    Flows::Log.event('flow.wait.started', run.session, node_type: node['type'], timer: wake_at.present?)
    nil
  end

  def finish(run, status, reason = nil)
    return hand_off(run.session, reason || 'handoff_node') && nil if status == :handed_off

    ending.complete(run.session)
    nil
  end

  def fail(run, code) = ending.fail(run.session, code) && nil

  def hand_off(session, reason) = ending.hand_off(session, reason)

  # The flow cannot run here now (feature or switch off, contact blocked): humans take the conversation.
  def unavailable(session)
    session ? hand_off(session, 'flow_unavailable') : hand_off_conversation('flow_unavailable')
  end

  def hand_off_conversation(reason) = ending.skip(bot, reason) && nil

  def ending = @ending ||= Flows::SessionEnd.new(@conversation)
end
