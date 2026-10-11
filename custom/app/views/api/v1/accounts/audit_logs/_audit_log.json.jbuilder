json.id entry.id
json.action entry.action
json.auditable_type entry.auditable_type
json.auditable_id entry.auditable_id
json.user_id entry.user_id
json.user_type entry.user_type
# Captured when the row was written, so the row stays attributable after the actor's own record is gone.
json.username entry.username
# The short event name Lynomia's own writers put here. The browser builds its label from type and action, so
# this is the only place a named event such as a credential rotation is legible.
json.comment entry.comment
json.audited_changes disclosure.changes(entry.audited_changes)
# Unix seconds: app/javascript/.../auditlogs/Index.vue:229 hands this to messageTimestamp, which is fromUnixTime.
json.created_at entry.created_at.to_i
# Coarse unless the account has `audit_log_ip_address`; nil when nothing usable was stored.
json.remote_address disclosure.address(entry.remote_address)

# The membership entries' label depends on whether the actor edited themselves, which the browser decides from
# the auditable's own user id (app/javascript/dashboard/helper/auditlogHelper.js:103,218). Nothing else about
# the audited record is disclosed, and a record that has since been deleted is null -- which is the signal the
# browser already reads to render the "deleted user" label.
json.auditable(entry.auditable.respond_to?(:user_id) ? { user_id: entry.auditable.user_id } : nil)
