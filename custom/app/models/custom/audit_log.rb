# Lynomia's audit record (docs/p-final/clean-room/specs/A-audit-trail-read.md,
# docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# This is the `audited` gem's own audit class -- config/initializers/audited.rb names it, so every `audited`
# declaration in the product writes one of these -- extended with the reads the account trail needs and with the
# two rules that hold for every entry however it was written:
#
#   * the actor's display name is captured at write time, so a row stays attributable after the person's own
#     record is deleted, and a machine credential, which is not a User at all, is still named;
#   * no credential reaches `audited_changes`. Package B's capture points exclude them by construction, and this
#     is the second line of defence for the six clean Lynomia writers and for the `audited` macro, which records
#     whatever columns a model declares -- including jsonb columns whose nested keys hold provider secrets
#     (Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS). AuditTrail::Secrets is the rule.
#
# `city`, `country` and `country_code` exist because the table is shared with upstream. Lynomia resolves no
# locations, so they stay unwritten and unread.
class Custom::AuditLog < Audited::Audit
  before_save :drop_secret_changes
  before_create :capture_actor_name

  # The account trail. Scoped from the authenticated account, never from a request parameter, and served by
  # index_audits_on_associated_and_created_at.
  #
  # An entry with no `associated` is installation-wide rather than one account's -- a plan's entitlements, for
  # instance (custom/app/services/billing/plan_audit.rb) -- so it is correctly invisible here.
  scope :for_account, ->(account) { where(associated_type: 'Account', associated_id: account.id) }
  scope :of_type, ->(types) { where(auditable_type: types) }
  scope :by_actor, ->(user_id) { where(user_id: user_id) }
  scope :occurred_between, ->(from, to) { where(created_at: from..to) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }

  private

  # `try` throughout: an actor is a User, a SuperAdmin on the same table, or a machine credential, and none of
  # them may be the one whose actions go unrecorded because its class answers a different method.
  def capture_actor_name
    self.username = actor_display_name if username.blank?
  end

  def actor_display_name
    user.try(:available_name).presence || user.try(:name).presence || user&.class&.name
  end

  def drop_secret_changes
    return unless audited_changes.is_a?(Hash)

    self.audited_changes = AuditTrail::Secrets.scrub(audited_changes)
  end
end
