# B16 -- a record destroyed by the asynchronous deletion path (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Upstream already threads the acting user and the request address into this job from both of its callers
# (app/controllers/api/v1/accounts/inboxes_controller.rb, app/services/conversations/delete_service.rb). What
# was missing is that the audit row written during `destroy!` had no way to see them, so it named nobody -- and
# an entry attributing a deletion to the background worker answers nobody's question.
#
# Rather than write a second entry after the fact, the actor is put where the record's own capture point will
# find it. One entry, from the same declaration that records every other change to that record, attributed to
# the person who asked.
#
# The purge is a different matter. Upstream pre-deletes the heavy associations -- an account's or an inbox's
# conversations, contacts and reporting events -- and auditing those would write a row per conversation for one
# operator action: noise, and a recording cost that grows with the size of the record's associations, which is
# the one thing package B §8 criterion 9 forbids. The operator's action is audited; its fan-out is not.
module Custom::DeleteObjectJob
  def perform(object, user = nil, ip = nil)
    AuditTrail::Capture.as_actor(user, ip) { super }
  end

  def purge_heavy_associations(object)
    AuditTrail::Capture.suppressed { super }
  end
end
