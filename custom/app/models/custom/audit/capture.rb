# What every Lynomia capture point declared with the `audited` macro has in common
# (docs/p-final/clean-room/specs/B-audit-event-capture.md §2, §6).
#
# Two obligations, neither of which the gem has:
#
# 1. Capture must not turn a successful product action into a failure. The gem writes its row from an
#    `after_create`/`after_update`/`after_destroy` callback, inside the product action's own transaction, so a
#    store that rejects the row would roll the action back. The savepoint is what makes the rescue true rather
#    than merely quiet: once a failed INSERT has raised, PostgreSQL has already marked the surrounding
#    transaction aborted, and rescuing without rolling back to a savepoint would just move the failure to the
#    product action's COMMIT.
#
# 2. A cascade is not an event. Deleting an inbox destroys every conversation in it, and a row per conversation
#    for one operator action is both noise and a recording cost that grows with the record's associations --
#    which package B §8 criterion 9 forbids. AuditTrail::Capture marks the fan-out; this is where the mark is
#    honoured.
#
# **Prepended, not included.** `audited` inserts the gem's own instance methods into the model when it runs,
# ahead of anything a concern merely includes, so an included override of `write_audit` is never reached. Being
# prepended to the model itself is what puts this in front of the gem.
module Custom::Audit::Capture
  private

  def write_audit(attrs)
    return if AuditTrail::Capture.suppressed?

    ActiveRecord::Base.transaction(requires_new: true) { super }
  rescue StandardError => e
    Rails.logger.error("[Lynomia::Audit] could not record #{attrs[:action]} on #{self.class.name}##{id}: #{e.class}")
    ChatwootExceptionTracker.new(e).capture_exception
    nil
  end
end
