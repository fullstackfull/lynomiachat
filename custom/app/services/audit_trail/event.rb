# A named Lynomia audit event, written by hand rather than by the `audited` macro
# (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Four of package B's capture points cannot be a model declaration: a sign-in and a sign-out are not changes to
# any row, and a deleted message must be recorded with LESS than the record held rather than with all of it.
# Those go through here, which is the same shape the six clean Lynomia writers use directly
# (custom/app/services/commerce/audit_trail.rb, custom/app/services/flows/audit.rb and the P11 billing writers)
# with package B's two obligations added:
#
#   * capture never turns a successful product action into a failure. The write is wrapped in a savepoint, so a
#     store that rejects it leaves the surrounding transaction usable and the action still commits;
#   * the failure is reported where operators look, and never to the end user.
#
# The actor is never a parameter. Package B §5: "The actor is recorded, not asserted. It comes from the
# authenticated request context, never from a parameter the caller supplies." So it, the originating address
# and the request id are all left to the record, which reads them from the same store the `audited` macro's
# rows read them from -- one mechanism, so a hand-written event and a declared one cannot disagree about who
# acted or where the request came from. A caller that knows the actor and is outside a request, as sign-out is,
# says so by wrapping the call in `Custom::AuditLog.as_user`.
module AuditTrail::Event
  # `action` is the verb the browser builds its label from, as `<auditable_type>:<action>` lower-cased
  # (app/javascript/dashboard/helper/auditlogHelper.js). It is therefore the frontend's vocabulary, not the
  # gem's: `sign_in` and `sign_out` are as legitimate here as `create` and `destroy`.
  def self.record(action:, auditable:, account:, comment: nil, changes: {})
    return if account.blank?

    write(
      auditable: auditable, associated: account, action: action.to_s,
      comment: comment, audited_changes: changes.deep_stringify_keys
    )
  end

  # `auditable_type` and `auditable_id` instead of the record itself, for the one caller whose subject is already
  # gone by the time the event can be described: the row has to name what was deleted without holding it.
  def self.record_removal(auditable_type:, auditable_id:, account:, comment: nil, changes: {})
    return if account.blank?

    write(
      auditable_type: auditable_type, auditable_id: auditable_id, associated: account,
      action: 'destroy', comment: comment, audited_changes: changes.deep_stringify_keys
    )
  end

  # A savepoint rather than a bare rescue: by the time a failed INSERT has been raised, the enclosing
  # transaction is already poisoned, and rescuing the exception without rolling back to a savepoint would only
  # move the failure to the product action's COMMIT.
  def self.write(attributes)
    ActiveRecord::Base.transaction(requires_new: true) { Custom::AuditLog.create!(attributes) }
  rescue StandardError => e
    Rails.logger.error(
      "[Lynomia::Audit] could not record #{attributes[:action]} on " \
      "#{attributes[:auditable_type] || attributes[:auditable]&.class&.name}: #{e.class}"
    )
    ChatwootExceptionTracker.new(e).capture_exception
    nil
  end
  private_class_method :write
end
