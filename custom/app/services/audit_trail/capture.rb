# The two pieces of context that decide what a capture records, for the paths that run outside a request
# (docs/p-final/clean-room/specs/B-audit-event-capture.md §4, §6).
#
# Both live in `Audited.store`, which is an ActiveSupport::CurrentAttributes store: thread-isolated and reset by
# the executor around every request and every job, so neither leaks between two pieces of work running at once.
#
# #as_actor exists for asynchronous destruction. The person who asked for an inbox to be deleted has gone by the
# time the worker performs it, and an entry blaming the worker is an entry that answers nobody's question.
#
# #suppressed exists for the cascade. Deleting an inbox destroys every conversation in it, and auditing each one
# would write a row per conversation for a single operator action -- which is both noise and a recording cost
# that grows with the size of the record's associations, the one thing package B §8 forbids. The operator's
# action is audited; its fan-out is not.
module AuditTrail::Capture
  SUPPRESSED = :lynomia_audit_suppressed

  def self.as_actor(user, remote_address = nil, &)
    previous_address = Audited.store[:current_remote_address]
    Audited.store[:current_remote_address] = remote_address if remote_address.present?
    Custom::AuditLog.as_user(user, &)
  ensure
    Audited.store[:current_remote_address] = previous_address
  end

  def self.suppressed
    previous = Audited.store[SUPPRESSED]
    Audited.store[SUPPRESSED] = true
    yield
  ensure
    Audited.store[SUPPRESSED] = previous
  end

  def self.suppressed?
    Audited.store[SUPPRESSED] == true
  end
end
