# The sign-in / sign-out half of Lynomia's audit log.
#
# Chatwoot Enterprise wrote these two events by hand, from
# `enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb`, because `User` is
# deliberately not attribute-audited: its `audited` declaration carried `unless: proc { |_u| true }`,
# whose only purpose was to register the class. Removing the overlay therefore took the whole "Access"
# family -- sign-in and sign-out -- out of a log that
# `custom/db/documentation/{en,ar}/administration/audit-logs.md` still describes as a record of
# "configuration changes and sign-ins". The eleven mirrored `audited` declarations in
# `custom/app/models/custom/audit/` cover the other three families; nothing covered this one.
#
# Relocated here unchanged in every field: same `audits` table through `Custom::AuditLog`, same
# `insert_all!` (so no model callback fires and `username` is written explicitly), one row per account
# the user belongs to, versions continuing that user's own sequence, one shared `request_uuid` and
# timestamp per request, and `remote_address` as the Audited sweeper captured it.
#
# Two deliberate differences from the Enterprise original, neither of them behavioural for the rows:
#
#   1. No `Enterprise::AuditLogSessionIpLookupJob` enqueue. That job resolved `remote_address` to a
#      city and country, needed the `ip_lookup` feature (`config/features.yml`, `enabled: false`) and
#      died with the overlay. `remote_address` is still recorded; `city`, `country` and `country_code`
#      stay null, exactly as `Custom::AuditLog` already documents for the reader.
#   2. The helpers are private. The Enterprise module left them public, which on a prepended
#      controller makes them candidate actions; nothing calls them from outside.
#
# The SAML guard that shared the Enterprise module is not relocated -- SAML left with the overlay.
module Custom::DeviseOverrides::SessionsController
  def render_create_success
    create_audit_event('sign_in')
    super
  end

  def destroy
    # `@resource` is set by DeviseTokenAuth's `before_action :set_user_by_token, only: [:destroy]`,
    # and its own `destroy` removes the ivar, so the row has to be written before `super`.
    create_audit_event('sign_out')
    super
  end

  private

  def create_audit_event(action)
    return unless @resource

    account_ids = @resource.accounts.ids
    return if account_ids.empty?

    # rubocop:disable Rails/SkipsModelValidations
    Custom::AuditLog.insert_all!(audit_event_rows(action, account_ids))
    # rubocop:enable Rails/SkipsModelValidations
  end

  def audit_event_rows(action, account_ids)
    base_version = Custom::AuditLog.unscoped.auditable_finder(@resource.id, 'User').maximum(:version) || 0
    request_uuid = ::Audited.store[:current_request_uuid].presence || SecureRandom.uuid
    created_at = Time.zone.now

    account_ids.each_with_index.map do |account_id, index|
      {
        auditable_id: @resource.id,
        auditable_type: 'User',
        user_id: @resource.id,
        user_type: 'User',
        username: @resource.email,
        action: action,
        associated_id: account_id,
        associated_type: 'Account',
        version: base_version + index + 1,
        request_uuid: request_uuid,
        remote_address: ::Audited.store[:current_remote_address],
        created_at: created_at
      }
    end
  end
end
