# Lynomia Flow Builder metrics (docs/flow-builder/05-runtime-and-session.md §observability): one structured log line per
# event, ids and timings only. Never a phone number, a message body, an answer or a token.
#
#   flow.execution.started / completed / handoff / failed / cancelled
#   flow.node.executed     node_type, result (an output, wait, or the finish status), duration_ms
#   flow.wait.started / resumed
module Flows::Log
  def self.event(name, session, **details)
    write({ event: name, account_id: session.account_id, flow_id: session.agent_bot_id, version_id: session.flow_version_id,
            session_id: session.id, conversation_id: session.conversation_id }.merge(details.compact))
  end

  # Test Mode (Flows::Simulator) shows the entries to the tester instead of logging them.
  def self.write(entry)
    return Flows::Simulator.record(entry) if Flows::Simulator.active?

    Rails.logger.info("[Lynomia::Flow] #{entry.to_json}")
  end

  def self.clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def self.ms(started) = ((clock - started) * 1000).round(1)
end
