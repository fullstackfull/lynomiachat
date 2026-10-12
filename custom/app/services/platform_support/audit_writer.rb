# The one place a Platform Support action reaches the audit trail
# (docs/platform-support/12-refresh-against-product-refinement.md §3 "Audit").
#
# WHY THIS EXISTS AT ALL, instead of `audited` on the models. `config/initializers/audited.rb` leaves
# `Audited.current_user_method` at the gem default, the Sweeper is installed on ActionController::Base, and it
# resolves the actor with Devise's `current_user` -- Devise scope `:user`. A Super Admin authenticates under
# scope `:super_admin`. So a declared `audited` macro here would produce rows attributed to nobody, or, with a
# co-resident tenant session acquired by one click from the Super Admin navigation, rows attributed to the
# TENANT principal and indistinguishable from a legitimate tenant-side edit. Both are silent. Hence: explicit
# writes, with an explicit actor, and the macro declared on no `platform_support_*` model.
#
# `associated` IS DELIBERATELY ABSENT. AuditTrail::Query serves `Custom::AuditLog.for_account(account)` to a
# tenant's own administrators, and that scope matches on `associated_type`/`associated_id`. A row with no
# `associated` is filed installation-wide and is therefore correctly invisible on the customer's Audit Logs
# page -- which is the whole point: operator activity about a customer is Lynomia's record, not the customer's.
# This is the same arrangement Billing::PlanAudit already uses, and Custom::AuditLog's own header documents it.
#
# The actor is a REQUIRED keyword and this class refuses without one, because there is no ambient actor worth
# inferring here (see above). For a staff action it is the acting agent's `User` -- the real Super Admin -- not
# the agent row, so the trail's `user_id`/`username` point at a person the `users` table knows.
#
# These writes are NOT best-effort: there is no `rescue`. Nothing downstream depends on the audit having
# happened, so if a decision cannot be recorded it did not happen.
class PlatformSupport::AuditWriter
  # Ids, enum values, counts, timestamps and the reference string only. Never a body, never a provider payload,
  # never a credential -- and AuditTrail::Secrets.scrub runs on every row as the second line of defence.
  def initialize(actor:)
    raise ArgumentError, 'An audit actor is required' if actor.nil?

    @actor = actor
  end

  def write(ticket, event, changes = {})
    Custom::AuditLog.create!(
      auditable: ticket,
      user: @actor,
      action: event == 'created' ? 'create' : 'update',
      comment: "platform_support.#{event}",
      audited_changes: payload(ticket, event).merge(changes.compact.transform_keys(&:to_s))
    )
  end

  private

  def payload(ticket, event)
    {
      'ticket_id' => ticket.id,
      'reference' => ticket.reference,
      'subject_account_id' => ticket.account_id,
      'status' => ticket.status,
      'priority' => ticket.priority,
      'category' => ticket.category,
      'event' => event
    }
  end
end
