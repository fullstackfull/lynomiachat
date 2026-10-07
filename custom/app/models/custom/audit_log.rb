# Lynomia's audit class. The `audited` gem is an OSS dependency (Gemfile:184) and the `audits` table ships in
# the OSS schema (db/schema.rb:264), so this is a subclass on the existing table, not a second audit store:
# rows written while Chatwoot's Enterprise overlay owned the class are the same rows.
#
# Carried over from Enterprise::AuditLog: `log_additional_information`, which is what fills `username` on every
# row and points an Account audit at itself, so the Lynomia writers (Flows::Audit, Commerce::AuditTrail) and the
# Template Manager's own `audited` declaration keep recording who acted.
#
# Deliberately not carried over: the IP geolocation hook, `location`, `masked_remote_address` and the
# `search_by_user` / `created_after` / `with_auditable_types` scopes. Those exist for Chatwoot's Enterprise audit
# log viewer, which Lynomia does not ship, and the geolocation path needs the `ip_lookup` feature
# (config/features.yml:32, enabled: false) plus an Enterprise job. The city/country columns stay null, as today.
class Custom::AuditLog < Audited::Audit
  after_save :log_additional_information

  private

  def log_additional_information
    # rubocop:disable Rails/SkipsModelValidations
    if auditable_type == 'Account' && auditable_id.present?
      update_columns(associated_type: auditable_type, associated_id: auditable_id, username: user&.email)
    else
      update_columns(username: user&.email)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
