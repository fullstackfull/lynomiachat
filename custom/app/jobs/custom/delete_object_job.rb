# Lynomia keeps Chatwoot's audit row for a deleted inbox or conversation after the Enterprise overlay goes, through
# the `prepend_mod_with` the OSS job already declares (app/jobs/delete_object_job.rb:43). The OSS job calls
# `process_post_deletion_tasks(object, user, ip)` after `object.destroy!` and leaves the body empty (:16), and two
# OSS call sites thread a user and an IP all the way through to it for no other purpose than this row:
# app/controllers/api/v1/accounts/inboxes_controller.rb:81 and app/services/conversations/delete_service.rb:6.
#
# It is also the only writer for `inbox:destroy` in the dashboard's activity map
# (app/javascript/dashboard/helper/auditlogHelper.js), because Custom::Audit::Inbox is declared
# `on: [:create, :update]` -- as Enterprise::Audit::Inbox was. Without this module that row type can never appear.
#
# Faithful port, with one necessary narrowing: the original listed `SlaPolicy` alongside Inbox and Conversation, and
# that model left with the Enterprise overlay. Nothing else changes -- `object.attributes` is recorded in full
# because neither `inboxes` nor `conversations` has a credential column, unlike the channel tables behind
# Custom::Channelable.
module Custom::DeleteObjectJob
  AUDITED_TYPES = %w[Inbox Conversation].freeze

  def process_post_deletion_tasks(object, user, ip)
    create_audit_entry(object, user, ip)
  end

  def create_audit_entry(object, user, ip)
    return unless AUDITED_TYPES.include?(object.class.to_s) && user.present?

    Custom::AuditLog.create(
      auditable: object,
      audited_changes: object.attributes,
      action: 'destroy',
      user: user,
      associated: object.account,
      remote_address: ip
    )
  end
end
