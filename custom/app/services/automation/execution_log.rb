# One structured log line per Lynomia automation evaluation (docs/automation/05-runtime-security-and-tenancy.md): the
# rule, its trigger, the outcome, how long it took and the id that ties it to its event. Ids only: no contact data, no
# Commerce payload, no token.
#
#   outcomes  executed (conditions matched, actions ran) | skipped (no match) | duplicate (this event already ran this
#             rule) | no_conversation (the contact has none to act on)
module Automation::ExecutionLog
  # `details`: started_at (Automation::ExecutionLog.clock when the evaluation began), actions (the names that ran).
  def self.write(rule, trigger, outcome, correlation_id, details = {})
    entry = { event: 'lynomia.automation.rule', account_id: rule.account_id, rule_id: rule.id, trigger: trigger, outcome: outcome,
              correlation_id: correlation_id }
    entry[:duration_ms] = ((clock - details[:started_at]) * 1000).round(1) if details[:started_at]
    entry[:actions] = details[:actions] if details[:actions]
    Rails.logger.info("[Lynomia::Automation] #{entry.to_json}")
  end

  def self.clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
