# Lynomia's audit class. The `audited` gem is an OSS dependency (Gemfile:184) and the `audits` table ships in
# the OSS schema (db/schema.rb:264), so this is a subclass on the existing table, not a second audit store:
# rows written while Chatwoot's Enterprise overlay owned the class are the same rows.
#
# Carried over from Enterprise::AuditLog: `log_additional_information`, which is what fills `username` on every
# row and points an Account audit at itself, so the Lynomia writers (Flows::Audit, Commerce::AuditTrail) and the
# Template Manager's own `audited` declaration keep recording who acted.
#
# Also carried over, for Lynomia's own audit log page (Settings -> Audit Logs): the four read scopes and
# `masked_remote_address`. Deliberately not carried over: the IP geolocation hook and `location`. That path needs
# the `ip_lookup` feature (config/features.yml:32, enabled: false) plus an Enterprise job, so `city`, `country`
# and `country_code` stay null and the page shows the address itself instead of a city.
class Custom::AuditLog < Audited::Audit
  after_save :log_additional_information

  scope :with_auditable_types, ->(types) { where(auditable_type: types) }
  scope :created_after, ->(time) { where(created_at: time..) }
  scope :created_before, ->(time) { where(created_at: ..time) }
  scope :search_by_user, lambda { |query|
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    joins("LEFT JOIN users ON users.id = audits.user_id AND audits.user_type = 'User'")
      .where('audits.username ILIKE :term OR users.name ILIKE :term OR users.email ILIKE :term', term: term)
  }

  # Shown to administrators by default; the full address needs the `audit_log_ip_address` account feature.
  def masked_remote_address
    return if remote_address.blank?

    ip = IPAddr.new(remote_address)
    if ip.ipv4?
      "#{ip.to_s.split('.')[0..2].join('.')}.x"
    else
      "#{ip.to_string.split(':')[0..3].join(':')}::"
    end
  rescue IPAddr::Error
    nil
  end

  private

  def log_additional_information
    # rubocop:disable Rails/SkipsModelValidations
    if auditable_type == 'Account' && auditable_id.present?
      update_columns(associated_type: auditable_type, associated_id: auditable_id, username: actor_username)
    else
      update_columns(username: actor_username)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end

  # `user` is polymorphic, so an actor is not always a User: a Platform App token edits a billing plan
  # (Billing::PlanAudit), and PlatformApp has a name and no email. Reading `user.email` unconditionally raised
  # NoMethodError from this after_save, which rolled the whole audit row back -- the actor with the least
  # accountability was the one whose actions went unrecorded. `user_type`/`user_id` identify the actor either
  # way; this column is what the Audit Logs page displays and searches.
  def actor_username
    user.try(:email).presence || user.try(:name).presence
  end
end
